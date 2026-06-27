// iroha-for-session — deterministic transcript extraction.
// Reads a Claude Code session JSONL (~/.claude/projects/<hash>/<id>.jsonl) and emits
// noise-free, deterministic views for /iroha:save-session. Read-only.
// stdout = the requested view only; diagnostics go to stderr.
//
// Usage: extract.ts <files|commands|meta|prompts|stats|tools|chat|all> <transcript.jsonl>
//
//   all       every view in ONE JSON object {meta, stats, files, commands, prompts, tools, chat},
//             parsing the (large) transcript ONCE — this is what /save-session calls.
//   files     unique files touched via Edit/Write/MultiEdit/NotebookEdit
//   commands  unique Bash commands (first line of each)
//   meta      {title, started, ended, cwd, gitBranch, model, sessionId}
//   prompts   the human's actual messages, in order — the You-side anchor for chat highlights.
//             Tool results, sidechains, harness meta turns (isMeta), system-injected wrappers,
//             peer-agent messages and injected compaction summaries are all excluded.
//   stats     {userTurns, assistantTurns, toolCalls, filesEdited, bashCommands, durationMin, …}
//   tools     per-tool usage tally, most-used first.
//   chat      the full cleaned chat (human turns + assistant text only).
//
// Transcripts can be truncated (a crash leaves an unfinished last line), so each line is parsed
// independently — malformed lines are skipped, never fatal.

import { existsSync, readFileSync } from "node:fs";

interface Block {
  type?: string;
  name?: string;
  text?: string;
  input?: { file_path?: string; notebook_path?: string; command?: string };
}
interface Rec {
  type?: string;
  isSidechain?: boolean;
  isMeta?: boolean;
  timestamp?: string;
  cwd?: string;
  gitBranch?: string;
  sessionId?: string;
  aiTitle?: string;
  message?: { role?: string; model?: string; content?: unknown };
}

// System-injected / peer-agent / compaction wrappers that are NOT the human's own turn.
const NOISE =
  /^\s*(<(command-message|command-name|task-notification|system-reminder|local-command-stdout|local-command-caveat|bash-input|bash-stdout|user-prompt-submit-hook|teammate-message|agent-message|tool-use-id|task-id)|Another Claude session sent a message:|This session is being continued)/;

export function parseRecords(file: string): Rec[] {
  const out: Rec[] = [];
  for (const line of readFileSync(file, "utf8").split("\n")) {
    if (line.trim() === "") continue;
    try {
      out.push(JSON.parse(line) as Rec);
    } catch {
      // truncated / malformed line — skip, never fatal.
    }
  }
  return out;
}

const notSidechain = (r: Rec) => r.isSidechain !== true;
const contentStr = (r: Rec): string | undefined =>
  typeof r.message?.content === "string" ? r.message.content : undefined;
const blocks = (r: Rec): Block[] =>
  Array.isArray(r.message?.content) ? (r.message.content as Block[]) : [];

function isRealUser(r: Rec): boolean {
  if (!notSidechain(r) || r.type !== "user" || r.isMeta === true) return false;
  const c = contentStr(r);
  return c !== undefined && !NOISE.test(c);
}

function toolUses(records: Rec[]): Block[] {
  const out: Block[] = [];
  for (const r of records) {
    if (!notSidechain(r) || r.type !== "assistant") continue;
    for (const b of blocks(r)) if (b.type === "tool_use") out.push(b);
  }
  return out;
}

// Collapse whitespace runs to a single space and trim (ASCII whitespace, matching jq's \s).
function norm(s: string): string {
  return s.replace(/[ \t\n\r\f\v]+/g, " ").replace(/^ +| +$/g, "");
}
// Slice by Unicode codepoint (matching jq's string[0:n]).
function sliceCp(s: string, n: number): string {
  return [...s].slice(0, n).join("");
}

function lastWith<T>(
  records: Rec[],
  pick: (r: Rec) => T | undefined,
): T | undefined {
  let v: T | undefined;
  for (const r of records) {
    const x = pick(r);
    if (x !== undefined && x !== null) v = x;
  }
  return v;
}

function sortedByTimestamp(records: Rec[]): Rec[] {
  return records
    .filter((r) => r.timestamp)
    .sort((a, b) =>
      (a.timestamp ?? "") < (b.timestamp ?? "")
        ? -1
        : (a.timestamp ?? "") > (b.timestamp ?? "")
          ? 1
          : 0,
    );
}

export function filesView(records: Rec[]): string[] {
  const items = toolUses(records)
    .filter(
      (b) => b.name && /^(Edit|Write|MultiEdit|NotebookEdit)$/.test(b.name),
    )
    .map((b) => ({
      verb: b.name === "Write" ? "write" : "edit",
      path: b.input?.file_path ?? b.input?.notebook_path,
    }))
    .filter((x): x is { verb: string; path: string } => x.path != null);
  // unique_by(.path): stable sort by path, keep the first of each path.
  const sorted = items
    .map((x, i) => ({ x, i }))
    .sort((a, b) =>
      a.x.path < b.x.path ? -1 : a.x.path > b.x.path ? 1 : a.i - b.i,
    );
  const seen = new Set<string>();
  const uniq: { verb: string; path: string }[] = [];
  for (const { x } of sorted) {
    if (seen.has(x.path)) continue;
    seen.add(x.path);
    uniq.push(x);
  }
  return uniq.map((x) => `- \`${x.path}\` (${x.verb})`);
}

export function commandsView(records: Rec[]): string[] {
  const cmds = toolUses(records)
    .filter((b) => b.name === "Bash")
    .map((b) => b.input?.command)
    .filter((c): c is string => c != null)
    .map((c) => c.split("\n")[0] as string);
  return [...new Set(cmds)].sort().map((c) => `- \`${c}\``);
}

export function promptsView(records: Rec[]): string[] {
  return records
    .filter(isRealUser)
    .map((r) => sliceCp(norm(contentStr(r) as string), 200))
    .filter((t) => t !== "")
    .map((t) => `- ${t}`);
}

export function toolsView(records: Rec[]): string[] {
  const counts = new Map<string, number>();
  for (const b of toolUses(records)) {
    const name = b.name ?? "";
    counts.set(name, (counts.get(name) ?? 0) + 1);
  }
  return [...counts.keys()]
    .sort()
    .map((name) => ({ name, n: counts.get(name) as number }))
    .sort((a, b) => b.n - a.n)
    .map((e) => `- \`${e.name}\` ×${e.n}`);
}

export function chatView(records: Rec[]): string[] {
  const out: string[] = [];
  for (const r of records) {
    if (!notSidechain(r)) continue;
    const turns: { role: string; text: string }[] = [];
    if (isRealUser(r)) {
      turns.push({ role: "You", text: contentStr(r) as string });
    } else if (r.type === "assistant") {
      for (const b of blocks(r)) {
        if (b.type === "text" && typeof b.text === "string")
          turns.push({ role: "Claude", text: b.text });
      }
    }
    for (const t of turns) {
      const c0 = norm(t.text);
      if (c0 === "") continue;
      const c = [...c0].length > 600 ? `${sliceCp(c0, 600)} … (truncated)` : c0;
      out.push(`**${t.role}** ${c}`);
    }
  }
  return out;
}

export function metaView(records: Rec[]) {
  const ts = sortedByTimestamp(records);
  const lastAiTitle = lastWith(records, (r) =>
    r.type === "ai-title" ? r.aiTitle : undefined,
  );
  const firstUserStr = records.find(
    (r) => r.type === "user" && typeof r.message?.content === "string",
  );
  return {
    title:
      lastAiTitle ??
      (firstUserStr
        ? (firstUserStr.message?.content as string)
        : "Untitled session"),
    started: ts[0]?.timestamp ?? null,
    ended: ts[ts.length - 1]?.timestamp ?? null,
    cwd: lastWith(records, (r) => r.cwd) ?? null,
    gitBranch: lastWith(records, (r) => r.gitBranch) ?? null,
    model:
      lastWith(records, (r) =>
        r.type === "assistant" ? r.message?.model : undefined,
      ) ?? null,
    sessionId: lastWith(records, (r) => r.sessionId) ?? null,
  };
}

export function statsView(records: Rec[]) {
  const ts = sortedByTimestamp(records);
  const tus = toolUses(records);
  const filesEdited = new Set(
    tus
      .filter(
        (b) => b.name && /^(Edit|Write|MultiEdit|NotebookEdit)$/.test(b.name),
      )
      .map((b) => b.input?.file_path ?? b.input?.notebook_path)
      .filter((p): p is string => p != null),
  ).size;
  const assistantTurns = records.filter(
    (r) =>
      notSidechain(r) &&
      r.type === "assistant" &&
      blocks(r).some((b) => b.type === "text"),
  ).length;
  const first = ts[0]?.timestamp;
  const last = ts[ts.length - 1]?.timestamp;
  const durationMin =
    ts.length > 1 && first && last
      ? Math.floor((Date.parse(last) - Date.parse(first)) / 60000)
      : 0;
  return {
    userTurns: records.filter(isRealUser).length,
    assistantTurns,
    toolCalls: tus.length,
    filesEdited,
    bashCommands: tus.filter((b) => b.name === "Bash").length,
    startedAt: first ?? null,
    endedAt: last ?? null,
    durationMin,
  };
}

const VIEWS = [
  "files",
  "commands",
  "meta",
  "prompts",
  "stats",
  "tools",
  "chat",
  "all",
] as const;
type View = (typeof VIEWS)[number];

function run(cmd: string, file: string): number {
  if (!existsSync(file)) {
    process.stderr.write(`extract.ts: no such file: ${file}\n`);
    return 1;
  }
  const records = parseRecords(file);
  const emitLines = (lines: string[]) =>
    process.stdout.write(lines.length ? `${lines.join("\n")}\n` : "");
  const emitJson = (obj: unknown) =>
    process.stdout.write(`${JSON.stringify(obj)}\n`);
  switch (cmd as View) {
    case "files":
      emitLines(filesView(records));
      return 0;
    case "commands":
      emitLines(commandsView(records));
      return 0;
    case "meta":
      emitJson(metaView(records));
      return 0;
    case "prompts":
      emitLines(promptsView(records));
      return 0;
    case "stats":
      emitJson(statsView(records));
      return 0;
    case "tools":
      emitLines(toolsView(records));
      return 0;
    case "chat":
      emitLines(chatView(records));
      return 0;
    case "all":
      emitJson({
        meta: metaView(records),
        stats: statsView(records),
        files: filesView(records),
        commands: commandsView(records),
        prompts: promptsView(records),
        tools: toolsView(records),
        chat: chatView(records),
      });
      return 0;
    default:
      process.stderr.write(`extract.ts: unknown command: ${cmd}\n`);
      return 2;
  }
}

if (import.meta.main) {
  const cmd = process.argv[2] ?? "";
  const file = process.argv[3] ?? "";
  if (cmd === "" || file === "") {
    process.stderr.write(
      "usage: extract.ts <files|commands|meta|prompts|stats|tools|chat|all> <transcript.jsonl>\n",
    );
    process.exit(2);
  }
  process.exit(run(cmd, file));
}
