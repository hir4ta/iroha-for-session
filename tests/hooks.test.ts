// Behavioral oracle (Bun test) for the hooks + recall orchestration + opt-in model gates. Ported
// 1:1 from the former tests/selftest.sh. Hooks are exercised as real subprocesses (stdin -> hook
// JSON on stdout), matching how Claude Code invokes them.
import { afterAll, beforeAll, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const SS = join(ROOT, "hooks/session-start.ts");
const RI = join(ROOT, "hooks/recall-inject.ts");
const CI = join(ROOT, "hooks/check-inject.ts");
const RECALL = join(ROOT, "scripts/_lib/recall.ts");
const EMBED = join(ROOT, "scripts/embed.ts");
const RERANK = join(ROOT, "scripts/rerank.ts");

type Run = { out: string; err: string; code: number };
function run(
  cmd: string[],
  opts: { input?: string; env?: Record<string, string> } = {},
): Run {
  const r = spawnSync(cmd[0] as string, cmd.slice(1), {
    input: opts.input,
    encoding: "utf8",
    env: opts.env ? { ...process.env, ...opts.env } : process.env,
  });
  return { out: r.stdout ?? "", err: r.stderr ?? "", code: r.status ?? 0 };
}
const mktmp = () => mkdtempSync(join(tmpdir(), "iroha-h."));
const CONFIG = join(ROOT, "scripts/_lib/config.ts");
const cfgSet = (dir: string, k: string, v: string) =>
  run(["bun", CONFIG, "set", k, v], { env: { IROHA_CONFIG_DIR: dir } });

const DECISION_ROW =
  '{"type":"decision","id":"389822c6-938a-812a-86fc-f709b3428ec2","topic":"連結","status":"Active","date":"2026-06-24","title":"連結: relation でなく URL","project":"demo","text":"MCP の relation 書き込みに既知バグがあるので URL プロパティで連結する"}';

let RIDATA: string; // recall_enabled, no rerank (FREE tier)
let RIHEAVY: string; // recall_enabled + rerank_enabled (HEAVY)
let RIDATA3: string; // decisions_ds_id only (no recall_enabled)
let RIDATA2: string; // empty (uninitialized)
let RIPROJ: string; // project root holding the one-row index
let RICACHE: string; // TMPDIR for per-prompt cache markers

beforeAll(() => {
  RIDATA = mktmp();
  RIHEAVY = mktmp();
  RIDATA3 = mktmp();
  RIDATA2 = mktmp();
  RIPROJ = mktmp();
  RICACHE = mktmp();
  cfgSet(RIDATA, "decisions_ds_id", "DSID");
  cfgSet(RIDATA, "session_ds_id", "SSID");
  cfgSet(RIDATA, "recall_enabled", "true");
  cfgSet(RIHEAVY, "decisions_ds_id", "DSID");
  cfgSet(RIHEAVY, "recall_enabled", "true");
  cfgSet(RIHEAVY, "rerank_enabled", "true");
  cfgSet(RIDATA3, "decisions_ds_id", "DSID");
  mkdirSync(join(RIPROJ, ".iroha"), { recursive: true });
  writeFileSync(join(RIPROJ, ".iroha", "index.ndjson"), `${DECISION_ROW}\n`);
});
afterAll(() => {
  for (const d of [RIDATA, RIHEAVY, RIDATA3, RIDATA2, RIPROJ, RICACHE])
    rmSync(d, { recursive: true, force: true });
});

// recall-inject driver (no claude/timeout — recall is pure-local).
function ri(
  prompt: string,
  sid: string,
  extraEnv: Record<string, string> = {},
  cfg = RIDATA,
): Run {
  return run(["bun", RI], {
    input: JSON.stringify({ prompt, session_id: sid, cwd: RIPROJ }),
    env: {
      CLAUDE_PLUGIN_ROOT: ROOT,
      IROHA_CONFIG_DIR: cfg,
      TMPDIR: RICACHE,
      ...extraEnv,
    },
  });
}

// ── session-start hook ─────────────────────────────────────────────────────────────────────────
test("session-start hook (state injection + save backlog + compaction + silence)", () => {
  const home = mktmp();
  const data = mktmp();
  const proj = mktmp();
  const hash = proj.replace(/\//g, "-");
  const projdir = join(home, ".claude", "projects", hash);
  mkdirSync(projdir, { recursive: true });
  mkdirSync(join(proj, ".iroha"), { recursive: true });
  writeFileSync(
    join(projdir, "old.jsonl"),
    [
      '{"type":"user","timestamp":"2026-06-20T10:00:00.000Z","isSidechain":false,"message":{"role":"user","content":"Fix the parser bug"}}',
      '{"type":"assistant","timestamp":"2026-06-20T10:01:00.000Z","isSidechain":false,"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"src/parser.ts"}}]}}',
      "",
    ].join("\n"),
  );
  writeFileSync(
    join(projdir, "trivial.jsonl"),
    [
      '{"type":"user","timestamp":"2026-06-21T09:00:00.000Z","isSidechain":false,"message":{"role":"user","content":"TRIVIAL-QA what is the time"}}',
      '{"type":"assistant","timestamp":"2026-06-21T09:00:30.000Z","isSidechain":false,"message":{"role":"assistant","content":[{"type":"text","text":"It is morning."}]}}',
      "",
    ].join("\n"),
  );
  writeFileSync(join(proj, ".iroha", "state.md"), "STATE-CONTENT-XYZ");
  const env = { CLAUDE_PLUGIN_ROOT: ROOT, IROHA_CONFIG_DIR: data, HOME: home };
  const hook = (extra: Record<string, string> = {}, source?: string) =>
    run(["bun", SS], {
      input: JSON.stringify({
        cwd: proj,
        session_id: "cur",
        ...(source ? { source } : {}),
      }),
      env: { ...env, ...extra },
    });

  const out = hook().out;
  expect(out).toContain("STATE-CONTENT-XYZ");
  expect(out).toContain("Fix the parser bug");
  expect(out).toContain("save-session");
  expect(out).not.toContain("TRIVIAL-QA");
  expect(out).toContain("Open items carried over");
  expect(out).toContain("hookSpecificOutput");

  mkdirSync(join(data, "saved"), { recursive: true });
  writeFileSync(join(data, "saved", "old"), "");
  expect(hook().out).not.toContain("not saved to Notion");

  writeFileSync(
    join(projdir, "cur.jsonl"),
    '{"type":"user","isSidechain":false,"message":{"role":"user","content":"COMPACT-RECAP-PROMPT please"}}\n',
  );
  const cout = hook({}, "compact").out;
  expect(cout).toContain("re-injected after compaction");
  expect(cout).toContain("COMPACT-RECAP-PROMPT");

  rmSync(join(projdir, "cur.jsonl"));
  rmSync(join(proj, ".iroha", "state.md"));
  rmSync(join(projdir, "old.jsonl"));
  rmSync(join(projdir, "trivial.jsonl"));
  expect(hook().out).toBe("");

  // missing CLAUDE_PLUGIN_ROOT must still exit 0 silently
  const r = run(["bun", SS], {
    input: '{"cwd":"/x","session_id":"y"}',
    env: { HOME: home },
  });
  expect(r.code).toBe(0);

  for (const d of [home, data, proj])
    rmSync(d, { recursive: true, force: true });
});

// ── recall-inject hook (FREE-tier local BM25: gate / consent / cache / abstain / inject) ─────────
test("recall-inject — injects the matched decision (shape, content, URL)", () => {
  const out = ri("relationプロパティで連結すべきか検討したい", "sid1").out;
  expect(out).toContain("hookSpecificOutput");
  expect(out).toContain("連結: relation でなく URL");
  expect(out).toContain("notion.so/389822c6938a812a86fcf709b3428ec2");
});
test("recall-inject — cache (one recall per prompt per session)", () => {
  expect(ri("relationプロパティで連結すべきか検討したい", "sidC").out).not.toBe(
    "",
  );
  expect(ri("relationプロパティで連結すべきか検討したい", "sidC").out).toBe("");
});
test("recall-inject — gates: short / slash / system pseudo-turns", () => {
  expect(ri("hi there", "sid2").out).toBe("");
  expect(ri("/iroha:recall some topic here", "sid3").out).toBe("");
  expect(
    ri("<task-notification> an async agent just finished its work", "sidT").out,
  ).toBe("");
  expect(
    ri("<system-reminder> background reference context, not a request", "sidS")
      .out,
  ).toBe("");
});
test("recall-inject — opt-out / abstain / minscore floor", () => {
  expect(
    ri("relationプロパティで連結すべきか別セッションで", "sidD", {
      IROHA_RECALL_DISABLE: "1",
    }).out,
  ).toBe("");
  expect(
    ri("deploy the kubernetes cluster to the aws region", "sid4").out,
  ).toBe("");
  expect(
    ri("relationで連結する設計", "sid8", { IROHA_RECALL_MINSCORE: "999" }).out,
  ).toBe("");
});
test("recall-inject — not initialized / consent gate", () => {
  expect(ri("relationプロパティで連結すべきか", "sid5", {}, RIDATA2).out).toBe(
    "",
  );
  expect(ri("relationプロパティで連結すべきか", "sid6", {}, RIDATA3).out).toBe(
    "",
  );
});
test("recall-inject — selfcheck (offline readiness probe)", () => {
  const sc = run(["bun", RI, "--selfcheck"], {
    env: { CLAUDE_PLUGIN_ROOT: ROOT, IROHA_CONFIG_DIR: RIDATA },
  });
  expect(sc.out).toContain("READY");
  expect(sc.out).toContain("config initialized");
  const sc2 = run(["bun", RI, "--selfcheck"], {
    env: { IROHA_CONFIG_DIR: RIDATA },
  }); // no CLAUDE_PLUGIN_ROOT
  expect(sc2.out).toContain("READY");
});

// ── opt-in model gates (bun + the .ts contract; graceful fallback to BM25) ────────────────────────
test("rerank gate — contract paths + BM25 fallback", () => {
  expect(
    run(["bun", RERANK], { input: '{"query":"x","docs":[]}' }).out.trim(),
  ).toBe("[]");
  expect(run(["bun", RERANK], { input: "not-json" }).code).toBe(2);
  expect(
    run(["bun", RERANK], {
      input: '{"query":"x","docs":[{"id":"a","text":"b"}]}',
      env: { IROHA_MODEL_DIR: mktmp() },
    }).code,
  ).toBe(3);
  // armed (RIHEAVY) but model absent -> MUST still inject the BM25 advisory hit.
  expect(
    ri(
      "relationプロパティで連結すべきか検討したい",
      "sidRR1",
      { IROHA_MODEL_DIR: mktmp() },
      RIHEAVY,
    ).out,
  ).toContain("連結: relation でなく URL");
});
test("embed gate — contract paths", () => {
  expect(
    run(["bun", EMBED], { input: '{"query":"x","docs":[]}' }).out.trim(),
  ).toBe("[]");
  expect(run(["bun", EMBED], { input: "not-json" }).code).toBe(2);
  expect(
    run(["bun", EMBED], {
      input: '{"query":"x","docs":[{"id":"a","text":"b"}]}',
      env: { IROHA_MODEL_DIR: mktmp() },
    }).code,
  ).toBe(3);
});

// ── recall.ts (FREE tier; HEAVY armed but no model keeps BM25, never drops one) ──────────────────
test("recall.ts — free tier returns the BM25 advisory hit", () => {
  const r = run(
    ["bun", RECALL, RIPROJ, "relationプロパティで連結すべきか", "3"],
    { env: { IROHA_CONFIG_DIR: RIDATA3 } },
  );
  expect(r.out).toContain("連結: relation でなく URL");
});
test("recall.ts — heavy armed + no model keeps the BM25 hit", () => {
  const r = run(
    ["bun", RECALL, RIPROJ, "relationプロパティで連結すべきか", "3"],
    {
      env: {
        IROHA_CONFIG_DIR: RIDATA3,
        IROHA_RECALL_FORCE_HEAVY: "1",
        IROHA_MODEL_DIR: mktmp(),
      },
    },
  );
  expect(r.out).toContain("連結: relation でなく URL");
});

// ── check-inject hook (write-time decision advisory: gate / consent / abstain / inject) ──────────
function ci(
  command: string,
  sid: string,
  extraEnv: Record<string, string> = {},
  cfg = RIDATA,
): Run {
  return run(["bun", CI], {
    input: JSON.stringify({
      tool_name: "Bash",
      tool_input: { command },
      session_id: sid,
      cwd: RIPROJ,
    }),
    env: {
      CLAUDE_PLUGIN_ROOT: ROOT,
      IROHA_CONFIG_DIR: cfg,
      TMPDIR: RICACHE,
      IROHA_RERANK_DISABLE: "1",
      ...extraEnv,
    },
  });
}
test("check-inject — gates, consent, cache, abstain, inject", () => {
  const cp = ci('git commit -m "relationで連結する設計を変更"', "cci1");
  expect(cp.out).toContain("連結: relation でなく URL");
  expect(cp.out).toContain("hookSpecificOutput");
  expect(ci("git status", "cci2").out).toBe(""); // only `git commit` fires
  expect(
    ci('git commit -m "relationで連結"', "cci3", { IROHA_CHECK_DISABLE: "1" })
      .out,
  ).toBe("");
  expect(ci('git commit -m "relationで連結する設計を変更"', "cci1").out).toBe(
    "",
  ); // cache: one per subject/session
  expect(
    ci('git commit -m "deploy the kubernetes cluster to aws"', "cci4").out,
  ).toBe(""); // no governing decision
  expect(ci('git commit -m "relationで連結"', "cci5", {}, RIDATA3).out).toBe(
    "",
  ); // consent gate
});
