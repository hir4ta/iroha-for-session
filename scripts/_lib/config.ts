// config.ts — read/write the plugin's persisted config (Notion DB / page ids).
// Lives at $HOME/.iroha/config.json (override the dir with IROHA_CONFIG_DIR).
// Importable library: pure JSON over a small file, no network. Holds only
// non-secret ids (auth is handled by the Notion MCP OAuth connection):
//
//   { "container_page_id": "...",
//     "session_db_id": "...",   "session_ds_id": "...",
//     "decisions_db_id": "...", "decisions_ds_id": "...",
//     "projects_db_id": "...",  "projects_ds_id": "...",
//     "states_folder_id": "...",   "digests_folder_id": "...",   // grouping pages (keep the
//                                                                // container tidy as projects/digests grow)
//     "state_pages": { "<project-key>": "<page_id>", ... } }

import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";

type Config = Record<string, unknown> & {
  state_pages?: Record<string, string>;
};

// Stable per-user location: same path whether invoked from a skill, a hook, or the
// CLI, and it survives plugin reinstalls. Override with IROHA_CONFIG_DIR for tests.
export function configPath(): string {
  const base = process.env.IROHA_CONFIG_DIR || join(homedir(), ".iroha");
  return join(base, "config.json");
}

// Create the file with an empty skeleton if missing or corrupt; return its path. A
// corrupt config.json (e.g. an interrupted write) is backed up and reset, so get/set
// and /iroha:init recover instead of failing forever.
export function configEnsure(): string {
  const f = configPath();
  mkdirSync(dirname(f), { recursive: true });
  if (!existsSync(f)) {
    writeFileSync(f, '{"state_pages":{}}\n');
    return f;
  }
  try {
    JSON.parse(readFileSync(f, "utf8"));
  } catch {
    try {
      renameSync(f, `${f}.corrupt.${process.pid}`);
    } catch {
      // best-effort backup; reset regardless so callers recover.
    }
    writeFileSync(f, '{"state_pages":{}}\n');
  }
  return f;
}

function readConfig(): Config {
  return JSON.parse(readFileSync(configEnsure(), "utf8")) as Config;
}

function writeConfig(cfg: Config): void {
  const f = configEnsure();
  const tmp = join(tmpdir(), `iroha-cfg.${process.pid}.${Date.now()}`);
  writeFileSync(tmp, JSON.stringify(cfg, null, 2));
  renameSync(tmp, f);
}

// configGet(key) -> value or "" (absent / non-string -> "").
export function configGet(key: string): string {
  const v = readConfig()[key];
  return typeof v === "string" ? v : "";
}

export function configSet(key: string, value: string): void {
  const cfg = readConfig();
  cfg[key] = value;
  writeConfig(cfg);
}

export function getStatePage(projectKey: string): string {
  const v = readConfig().state_pages?.[projectKey];
  return typeof v === "string" ? v : "";
}

export function setStatePage(projectKey: string, pageId: string): void {
  const cfg = readConfig();
  cfg.state_pages = { ...(cfg.state_pages ?? {}), [projectKey]: pageId };
  writeConfig(cfg);
}

// configValidate() -> issue strings (empty list = clean).
// OFFLINE shape check on the stored Notion ids: a non-empty but MALFORMED id (e.g. the literal
// "DSID" placeholder, or a truncated value) passes every "is it set / non-empty?" check yet makes
// the canonical Notion calls fail silently. Empty ids are fine (a fresh config costs nothing). The
// complementary network "does this id resolve?" check belongs in audit.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HEX32 = /^[0-9a-f]{32}$/i;
export function configValidate(): string[] {
  const cfg = readConfig();
  const issues: string[] = [];
  for (const k of ["session_ds_id", "decisions_ds_id", "projects_ds_id"]) {
    const v = cfg[k];
    if (typeof v !== "string" || v === "") continue;
    if (!UUID.test(v))
      issues.push(
        `config: ${k} is not a valid Notion data-source id (UUID): "${v}" — run /iroha:init to repair (a malformed id breaks /iroha:recall, /iroha:audit, and decision saves)`,
      );
  }
  for (const k of [
    "container_page_id",
    "session_db_id",
    "decisions_db_id",
    "projects_db_id",
    "states_folder_id",
    "digests_folder_id",
  ]) {
    const v = cfg[k];
    if (typeof v !== "string" || v === "") continue;
    if (!HEX32.test(v.replace(/-/g, "")))
      issues.push(
        `config: ${k} is not a valid Notion id (32-hex): "${v}" — run /iroha:init to repair`,
      );
  }
  return issues;
}

// stateMdPath(root) -> the project's State mirror, kept IN THE REPO (<root>/.iroha/state.md).
// Committed so a teammate who pulls it gets the latest State injected by their SessionStart hook,
// which cannot reach Notion. Commit this file.
export function stateMdPath(root: string): string {
  return join(root, ".iroha", "state.md");
}

// savedDir() -> directory of per-session "saved" markers (per-machine, in $HOME).
export function savedDir(): string {
  return join(dirname(configPath()), "saved");
}

// transcriptPath(root, sid) -> this session's transcript JSONL, or "".
// Claude Code stores it at $HOME/.claude/projects/<root-with-each-/-as-->/<session-id>.jsonl.
// Resolve that path DETERMINISTICALLY (no glob); only if the project root moved since launch do we
// fall back to a BOUNDED search by session id.
export function transcriptPath(root: string, sid: string): string {
  const projects = join(homedir(), ".claude", "projects");
  const direct = join(projects, root.replace(/\//g, "-"), `${sid}.jsonl`);
  if (existsSync(direct)) return direct;
  // Bounded fallback: one level of project dirs, look for <sid>.jsonl.
  try {
    for (const d of readdirSync(projects)) {
      const p = join(projects, d, `${sid}.jsonl`);
      if (existsSync(p)) return p;
    }
  } catch {
    // projects dir absent -> no transcript.
  }
  return "";
}

// CLI: usable from skills/hooks as `bun config.ts <cmd> ...`. Each case returns the process exit
// code (so there is no fallthrough and no unreachable post-exit break).
function runCli(): number {
  const [cmd, a, b] = process.argv.slice(2);
  const write = (s: string) => process.stdout.write(s);
  switch (cmd) {
    case "state-md-path":
      write(stateMdPath(a ?? ""));
      return 0;
    case "saved-dir":
      write(savedDir());
      return 0;
    case "transcript-path":
      write(transcriptPath(a ?? "", b ?? ""));
      return 0;
    case "get":
      write(configGet(a ?? ""));
      return 0;
    case "set":
      configSet(a ?? "", b ?? "");
      return 0;
    case "get-state":
      write(getStatePage(a ?? ""));
      return 0;
    case "set-state":
      setStatePage(a ?? "", b ?? "");
      return 0;
    case "validate": {
      const issues = configValidate();
      for (const line of issues) console.log(line);
      return issues.length === 0 ? 0 : 1;
    }
    case "path":
      write(configPath());
      return 0;
    default:
      process.stderr.write(
        "usage: config.ts <get|set|get-state|set-state|validate|path|state-md-path|saved-dir|transcript-path> ...\n",
      );
      return 2;
  }
}

// Guarded so importing is a no-op.
if (import.meta.main) process.exit(runCli());
