// Behavioral oracle (Bun test) for the deterministic library + extract CLIs. Ported 1:1 from the
// former tests/selftest.sh — every eq/has/hasnt is one expect. Exercises the real `bun <script>.ts`
// CLIs (what skills invoke), parsing JSON natively instead of jq.
import { expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..");
const EXTRACT = join(ROOT, "scripts/extract.ts");
const CONFIG = join(ROOT, "scripts/_lib/config.ts");
const INDEX = join(ROOT, "scripts/_lib/index.ts");
const SEARCH = join(ROOT, "scripts/_lib/search.ts");
const INTEG = join(ROOT, "scripts/_lib/integrity.ts");
const STATELINT = join(ROOT, "scripts/_lib/state-lint.ts");
const SESSIONLINT = join(ROOT, "scripts/_lib/session-lint.ts");
const LINKLINT = join(ROOT, "scripts/_lib/link-lint.ts");
const CHATCHUNKS = join(ROOT, "scripts/chat-chunks.ts");
const FIX = join(import.meta.dir, "fixtures", "sample.jsonl");

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
const bun = (
  args: string[],
  opts?: { input?: string; env?: Record<string, string> },
) => run(["bun", ...args], opts);
const lines = (s: string) => s.split("\n").filter((l) => l !== "");
const mktmp = () => mkdtempSync(join(tmpdir(), "iroha-t."));

// ── extract: meta / files / commands / prompts / stats / tools / chat ──────────────────────────
test("extract meta", () => {
  const meta = JSON.parse(bun([EXTRACT, "meta", FIX]).out);
  expect(meta.title).toBe("Add login endpoint");
  expect(meta.sessionId).toBeTruthy();
});
test("extract files (deduped)", () => {
  const out = bun([EXTRACT, "files", FIX]).out;
  expect(out).toContain("src/login.ts");
  expect(lines(out).filter((l) => l.includes("src/login.ts")).length).toBe(1);
});
test("extract commands (first line only)", () => {
  const out = bun([EXTRACT, "commands", FIX]).out;
  expect(out).toContain("npm test");
  expect(out).not.toContain("echo done");
});
test("extract prompts (human's real messages — the You-anchor)", () => {
  const out = bun([EXTRACT, "prompts", FIX]).out;
  expect(out).toContain("Please add a login endpoint");
  for (const noise of [
    "FILE WRITTEN",
    "NOISE-TASKNOTIF",
    "NOISE-CAVEAT",
    "NOISE-ISMETA",
    "NOISE-TEAMMATE",
    "NOISE-COMPACT",
  ])
    expect(out).not.toContain(noise);
});
test("extract stats (metrics dashboard numbers)", () => {
  const s = JSON.parse(bun([EXTRACT, "stats", FIX]).out);
  expect(s.userTurns).toBe(1);
  expect(s.filesEdited).toBe(1);
  expect(s.durationMin).toBe(5);
});
test("extract tools (per-tool tally)", () => {
  expect(bun([EXTRACT, "tools", FIX]).out).toContain("Bash");
});
test("extract chat (cleaned full chat, no noise)", () => {
  const out = bun([EXTRACT, "chat", FIX]).out;
  expect(out).toContain("Please add a login endpoint");
  expect(out).toContain("the endpoint is added");
  for (const noise of [
    "SECRET THOUGHTS",
    "FILE WRITTEN",
    "SIDECHAIN",
    "NOISE-CAVEAT",
    "NOISE-ISMETA",
    "NOISE-TEAMMATE",
    "NOISE-COMPACT",
  ])
    expect(out).not.toContain(noise);
});
test("extract all — one-pass aggregate equals the individual views", () => {
  const all = JSON.parse(bun([EXTRACT, "all", FIX]).out);
  expect(all.meta).toEqual(JSON.parse(bun([EXTRACT, "meta", FIX]).out));
  expect(all.stats).toEqual(JSON.parse(bun([EXTRACT, "stats", FIX]).out));
  expect(all.files).toEqual(lines(bun([EXTRACT, "files", FIX]).out));
  expect(all.commands).toEqual(lines(bun([EXTRACT, "commands", FIX]).out));
  expect(all.prompts).toEqual(lines(bun([EXTRACT, "prompts", FIX]).out));
  expect(all.tools).toEqual(lines(bun([EXTRACT, "tools", FIX]).out));
  expect(all.chat).toEqual(lines(bun([EXTRACT, "chat", FIX]).out));
});
test("extract tolerates truncated / malformed lines", () => {
  const broken = join(mktmp(), "broken.jsonl");
  writeFileSync(
    broken,
    `${readFileSync(FIX, "utf8")}GARBAGE-NOT-JSON\n{"type":"assistant","truncated-no-close\n`,
  );
  const f = bun([EXTRACT, "files", broken]);
  expect(f.code).toBe(0);
  expect(f.out).toContain("src/login.ts");
  const m = JSON.parse(bun([EXTRACT, "meta", broken]).out);
  expect(m.title).toBe("Add login endpoint");
});
test("chat-chunks — turn-boundary split, every turn kept, manifest correct", () => {
  // perChunk=1 -> one chunk per turn (the split is on turn boundaries, never mid-turn).
  const r1 = JSON.parse(bun([CHATCHUNKS, FIX, mktmp(), "1"]).out);
  expect(r1.totalTurns).toBeGreaterThan(0);
  expect(r1.chunkCount).toBe(r1.totalTurns);
  expect(r1.files.length).toBe(r1.chunkCount);
  expect(readFileSync(r1.files[0], "utf8")).toMatch(/^\*\*(You|Claude)\*\* /);
  // big perChunk -> a single chunk holding ALL turns as blank-line-separated paragraphs.
  const r2 = JSON.parse(bun([CHATCHUNKS, FIX, mktmp(), "100"]).out);
  expect(r2.chunkCount).toBe(1);
  expect(r2.totalTurns).toBe(r1.totalTurns);
  expect(readFileSync(r2.files[0], "utf8").split("\n\n").length).toBe(
    r2.totalTurns,
  );
});

// ── config: helper roundtrip + self-heal + validate + transcript-path ──────────────────────────
test("config helper (roundtrip, self-heal, isolated dir)", () => {
  const dir = mktmp();
  const env = { IROHA_CONFIG_DIR: dir };
  bun([CONFIG, "set", "session_db_id", "DB123"], { env });
  expect(bun([CONFIG, "get", "session_db_id"], { env }).out).toBe("DB123");
  expect(bun([CONFIG, "get", "nonexistent_key"], { env }).out).toBe("");
  bun([CONFIG, "set-state", "/repo/foo", "PAGE9"], { env });
  expect(bun([CONFIG, "get-state", "/repo/foo"], { env }).out).toBe("PAGE9");
  expect(bun([CONFIG, "get-state", "/repo/bar"], { env }).out).toBe("");
  writeFileSync(join(dir, "config.json"), "GARBAGE"); // corrupt -> self-heal
  expect(bun([CONFIG, "get", "session_db_id"], { env }).out).toBe("");
  bun([CONFIG, "set", "session_db_id", "DB2"], { env });
  expect(bun([CONFIG, "get", "session_db_id"], { env }).out).toBe("DB2");
});
test("config validate (id shape catches placeholder/truncated ids)", () => {
  const dir = mktmp();
  const env = { IROHA_CONFIG_DIR: dir };
  bun(
    [CONFIG, "set", "session_ds_id", "6b5fc3c8-de78-4c5f-afc6-2e1e226f9378"],
    { env },
  );
  bun(
    [CONFIG, "set", "decisions_ds_id", "34809d44-346f-4d4f-9fd6-8c9c2796e2c0"],
    { env },
  );
  bun([CONFIG, "set", "decisions_db_id", "128c8c81e60d4443a82cabfd84eb243f"], {
    env,
  });
  expect(bun([CONFIG, "validate"], { env }).code).toBe(0);
  bun([CONFIG, "set", "decisions_ds_id", "DSID"], { env });
  expect(bun([CONFIG, "validate"], { env }).code).toBe(1);
  expect(bun([CONFIG, "validate"], { env }).out).toContain("decisions_ds_id");
  bun(
    [CONFIG, "set", "decisions_ds_id", "34809d44-346f-4d4f-9fd6-8c9c2796e2c0"],
    { env },
  );
  bun([CONFIG, "set", "session_db_id", "not-32-hex"], { env });
  expect(bun([CONFIG, "validate"], { env }).code).toBe(1);
  bun([CONFIG, "set", "session_db_id", "c58dc1018eb54393bc67bd1a6fec6551"], {
    env,
  });
  bun([CONFIG, "set", "states_folder_id", "STATES"], { env });
  expect(bun([CONFIG, "validate"], { env }).code).toBe(1);
  expect(bun([CONFIG, "validate"], { env }).out).toContain("states_folder_id");
  expect(
    bun([CONFIG, "validate"], { env: { IROHA_CONFIG_DIR: mktmp() } }).code,
  ).toBe(0); // fresh
});
test("transcript-path (deterministic locate; bounded fallback; never globs)", () => {
  const home = mktmp();
  const root = "/Users/demo/Projects/app";
  const hash = root.replace(/\//g, "-");
  mkdirSync(join(home, ".claude", "projects", hash), { recursive: true });
  mkdirSync(join(home, ".claude", "projects", "-other-proj"), {
    recursive: true,
  });
  writeFileSync(join(home, ".claude", "projects", hash, "sidA.jsonl"), "");
  writeFileSync(
    join(home, ".claude", "projects", "-other-proj", "sidB.jsonl"),
    "",
  );
  const env = { HOME: home };
  expect(bun([CONFIG, "transcript-path", root, "sidA"], { env }).out).toBe(
    join(home, ".claude/projects", hash, "sidA.jsonl"),
  );
  expect(
    bun([CONFIG, "transcript-path", "/moved/since/launch", "sidB"], { env })
      .out,
  ).toBe(join(home, ".claude/projects/-other-proj/sidB.jsonl"));
  expect(bun([CONFIG, "transcript-path", root, "nosuchsid"], { env }).out).toBe(
    "",
  );
});

// ── index: upsert by id / find-topic / list / chain ────────────────────────────────────────────
test("index (upsert by id, find-topic, list, supersede chain)", () => {
  const root = mktmp();
  const up = (...a: string[]) => bun([INDEX, "upsert", root, ...a]);
  up(
    "decision",
    "dec1",
    "linking",
    "Active",
    "2026-06-24",
    "linking: URL",
    "demo",
  );
  up(
    "decision",
    "dec2",
    "runtime",
    "Active",
    "2026-06-24",
    "runtime: bash",
    "demo",
  );
  up(
    "session",
    "ses1",
    "",
    "Complete",
    "2026-06-25",
    "2026-06-25 eval",
    "demo",
  );
  up(
    "decision",
    "dec1",
    "linking",
    "Superseded",
    "2026-06-24",
    "linking: URL",
    "demo",
  ); // replace in place
  expect(
    lines(bun([INDEX, "list", root]).out).filter((l) =>
      l.includes('"id":"dec1"'),
    ).length,
  ).toBe(1);
  expect(
    JSON.parse(bun([INDEX, "find-topic", root, "linking"]).out).status,
  ).toBe("Superseded");
  expect(JSON.parse(bun([INDEX, "find-topic", root, "RUNTIME"]).out).id).toBe(
    "dec2",
  ); // ASCII case-insensitive
  expect(bun([INDEX, "find-topic", root, "missing-topic"]).out).toBe("");
  expect(
    lines(bun([INDEX, "list", root, "decision"]).out).filter((l) =>
      l.includes('"type":"decision"'),
    ).length,
  ).toBe(2);
  expect(
    lines(bun([INDEX, "list", root, "session"]).out).filter((l) =>
      l.includes('"type":"session"'),
    ).length,
  ).toBe(1);
  for (const l of lines(bun([INDEX, "list", root]).out))
    expect(() => JSON.parse(l)).not.toThrow();
  up(
    "decision",
    "chA",
    "topicX",
    "Superseded",
    "2026-06-24",
    "topicX: v1",
    "demo",
    "first",
    "",
  );
  up(
    "decision",
    "chB",
    "topicX",
    "Superseded",
    "2026-06-25",
    "topicX: v2",
    "demo",
    "second",
    "chA",
  );
  up(
    "decision",
    "chC",
    "topicX",
    "Active",
    "2026-06-26",
    "topicX: v3",
    "demo",
    "third",
    "chB",
  );
  const topicX = lines(bun([INDEX, "find-topic", root, "topicX"]).out).map(
    (l) => JSON.parse(l),
  );
  expect(topicX.find((r) => r.id === "chC").supersedes).toBe("chB");
  expect(
    lines(bun([INDEX, "chain", root, "chC"]).out)
      .map((l) => JSON.parse(l).id)
      .join(","),
  ).toBe("chC,chB,chA");
  expect(
    lines(bun([INDEX, "chain", root, "chA"]).out)
      .map((l) => JSON.parse(l).id)
      .join(","),
  ).toBe("chA");
  expect(topicX.find((r) => r.id === "chA").supersedes ?? "null").toBe("null");
});

// ── index: typed query subcommands (has / active / dup-topics / in-range) ─────────────────────────
test("index has/active/dup-topics/in-range (typed replacements for shell jq/grep)", () => {
  const root = mktmp();
  const up = (...a: string[]) => bun([INDEX, "upsert", root, ...a]);
  up("decision", "d1", "alpha", "Active", "2026-06-10", "alpha: x", "demo");
  up("decision", "d2", "beta", "Active", "2026-06-20", "beta: y", "demo");
  up("decision", "d3", "Alpha", "Active", "2026-06-25", "alpha: z", "demo"); // dup topic (ASCII-ci) of d1
  up("decision", "d4", "gamma", "Superseded", "2026-06-21", "gamma: w", "demo");
  up("session", "s1", "", "Complete", "2026-06-15", "2026-06-15 work", "demo");

  // has: present -> exit 0, absent / empty id / wrong type -> exit 1, any-type with "" -> match
  expect(bun([INDEX, "has", root, "decision", "d1"]).code).toBe(0);
  expect(bun([INDEX, "has", root, "decision", "nope"]).code).toBe(1);
  expect(bun([INDEX, "has", root, "decision", ""]).code).toBe(1);
  expect(bun([INDEX, "has", root, "session", "d1"]).code).toBe(1);
  expect(bun([INDEX, "has", root, "", "s1"]).code).toBe(0);

  // active: only Active rows of the type (d4 Superseded excluded)
  const active = lines(bun([INDEX, "active", root, "decision"]).out).map((l) =>
    JSON.parse(l),
  );
  expect(
    active
      .map((r) => r.id)
      .sort()
      .join(","),
  ).toBe("d1,d2,d3");

  // dup-topics: alpha has 2 Active (d1 + d3, ASCII case-insensitive); beta/gamma do not
  expect(bun([INDEX, "dup-topics", root]).out.trim()).toBe("alpha");

  // in-range: inclusive [start,end], NEWEST FIRST (d4=06-21, d2=06-20, s1=06-15)
  const range = lines(
    bun([INDEX, "in-range", root, "2026-06-15", "2026-06-21"]).out,
  ).map((l) => JSON.parse(l));
  expect(range.map((r) => r.id).join(",")).toBe("d4,d2,s1");
  // type filter
  const rangeDec = lines(
    bun([INDEX, "in-range", root, "2026-06-15", "2026-06-21", "decision"]).out,
  ).map((l) => JSON.parse(l));
  expect(rangeDec.map((r) => r.id).join(",")).toBe("d4,d2");
  // type + status filter (only Active decisions in window -> d2; d4 is Superseded)
  const rangeActive = lines(
    bun([
      INDEX,
      "in-range",
      root,
      "2026-06-15",
      "2026-06-21",
      "decision",
      "Active",
    ]).out,
  ).map((l) => JSON.parse(l));
  expect(rangeActive.map((r) => r.id).join(",")).toBe("d2");
});

// ── search: BM25 (CJK bigram, text field, status weight, abstention) ────────────────────────────
function searchRoot(): string {
  const root = mktmp();
  mkdirSync(join(root, ".iroha"), { recursive: true });
  writeFileSync(
    join(root, ".iroha", "index.ndjson"),
    [
      '{"type":"decision","id":"d1","topic":"連結","status":"Active","date":"2026-06-24","title":"連結: relation でなく URL","project":"demo","text":"relation は MCP 書き込みバグがあるので URL プロパティで Session と Decision をつなぐ"}',
      '{"type":"decision","id":"d2","topic":"Notion 連携","status":"Active","date":"2026-06-24","title":"Notion 連携: MCP 一本","project":"demo","text":"API トークンの二重セットアップを避けるため認証は Notion MCP の OAuth に統一する"}',
      '{"type":"decision","id":"d3","topic":"リコール","status":"Superseded","date":"2026-06-24","title":"リコール: ローカル grep","project":"demo","text":"ローカル grep で検索する旧方針"}',
      '{"type":"decision","id":"d4","topic":"リコール","status":"Active","date":"2026-06-25","title":"リコール: hybrid","project":"demo","text":"notion-search と index を融合して検索する"}',
      '{"type":"session","id":"s1","topic":"","status":"Complete","date":"2026-06-25","title":"2026-06-25 — 認証フローの設計","project":"demo","text":"OAuth の認証フローを設計した"}',
      "",
    ].join("\n"),
  );
  return root;
}
test("search (CJK bigram, text field, status weight, abstention, valid+ordered)", () => {
  const root = searchRoot();
  const first = (q: string, type = "", n = 3) =>
    JSON.parse(lines(bun([SEARCH, root, q, type, String(n)]).out)[0] as string);
  expect(first("URLで連結したい", "decision").id).toBe("d1");
  expect(first("APIトークンは必要か", "decision").id).toBe("d2");
  expect(first("リコール", "decision").id).toBe("d4"); // Active outranks Superseded
  expect(bun([SEARCH, root, "oauth flow", "", "3"]).out).toContain("s1"); // English token
  const sess = lines(bun([SEARCH, root, "認証", "session", "3"]).out).map(
    (l) => JSON.parse(l).type,
  );
  expect([...new Set(sess)].join(",")).toBe("session");
  expect(bun([SEARCH, root, "zzqqxx vvbbnn wwkkpp", "", "3"]).out).toBe(""); // abstain
  const scored = lines(
    bun([SEARCH, root, "リコール 検索 連結 認証", "", "5"]).out,
  ).map((l) => JSON.parse(l).score);
  expect(scored).toEqual([...scored].sort((a, b) => b - a)); // descending
});

// ── integrity: malformed / dup-id / dup-active / State-link / lineage ───────────────────────────
function intRoot(rows: string[], state?: string): string {
  const root = mktmp();
  mkdirSync(join(root, ".iroha"), { recursive: true });
  writeFileSync(
    join(root, ".iroha", "index.ndjson"),
    rows.join("\n") + (rows.length ? "\n" : ""),
  );
  if (state !== undefined)
    writeFileSync(join(root, ".iroha", "state.md"), state);
  return root;
}
const SESSROW =
  '{"type":"session","id":"38a822c6-938a-811e-b58a-d62cc504920a","topic":"","status":"Complete","date":"2026-06-25","title":"2026-06-25 — x"}';
const STATE_OK = [
  "**Latest (2026-06-25):** x.",
  "## Recent sessions",
  "- [2026-06-25 — x](https://www.notion.so/38a822c6938a811eb58ad62cc504920a)",
  "## Unfinished / Next",
  "- [ ] y",
  "## Decisions",
  "- [Decisions DB](https://www.notion.so/128c8c81e60d4443a82cabfd84eb243f)",
].join("\n");
test("integrity — clean baseline + ignores the Decisions-DB link", () => {
  const root = intRoot(
    [
      '{"type":"decision","id":"d1","topic":"連結","status":"Active","date":"2026-06-24","title":"連結: URL"}',
      '{"type":"decision","id":"d2","topic":"runtime","status":"Active","date":"2026-06-24","title":"runtime: bash"}',
      SESSROW,
    ],
    STATE_OK,
  );
  const r = bun([INTEG, root]);
  expect(r.code).toBe(0);
  expect(r.out).not.toContain("128c8c81");
});
test("integrity — duplicate Active topic flagged; superseded sibling OK", () => {
  const dup = intRoot(
    [
      '{"type":"decision","id":"d1","topic":"連結","status":"Active","date":"2026-06-24","title":"連結: URL"}',
      '{"type":"decision","id":"d2","topic":"runtime","status":"Active","date":"2026-06-24","title":"runtime: bash"}',
      SESSROW,
      '{"type":"decision","id":"d3","topic":"連結","status":"Active","date":"2026-06-25","title":"連結: dup"}',
    ],
    STATE_OK,
  );
  expect(bun([INTEG, dup]).code).toBe(1);
  expect(bun([INTEG, dup]).out).toContain("duplicate Active");
  const ok = intRoot(
    [
      '{"type":"decision","id":"d1","topic":"連結","status":"Active","date":"2026-06-24","title":"連結: URL"}',
      '{"type":"decision","id":"d0","topic":"連結","status":"Superseded","date":"2026-06-20","title":"連結: 旧"}',
      SESSROW,
    ],
    STATE_OK,
  );
  expect(bun([INTEG, ok]).code).toBe(0);
});
test("integrity — lineage ok / dangling supersedes / dup id / malformed / dangling State", () => {
  const lineageOk = intRoot(
    [
      '{"type":"decision","id":"d0","topic":"連結","status":"Superseded","date":"2026-06-20","title":"連結: 旧"}',
      '{"type":"decision","id":"d1","topic":"連結","status":"Active","date":"2026-06-24","title":"連結: URL","supersedes":"d0"}',
      SESSROW,
    ],
    STATE_OK,
  );
  expect(bun([INTEG, lineageOk]).code).toBe(0);
  const dangSup = intRoot(
    [
      '{"type":"decision","id":"d1","topic":"連結","status":"Active","date":"2026-06-24","title":"連結: URL","supersedes":"d0"}',
      '{"type":"decision","id":"d0","topic":"連結","status":"Superseded","date":"2026-06-20","title":"連結: 旧"}',
      SESSROW,
      '{"type":"decision","id":"d9","topic":"x","status":"Active","date":"2026-06-25","title":"x","supersedes":"ghost"}',
    ],
    STATE_OK,
  );
  expect(bun([INTEG, dangSup]).out).toContain("broken lineage");
  const dupId = intRoot([
    '{"type":"decision","id":"d1","topic":"a","status":"Active","date":"2026-06-24","title":"a"}',
    '{"type":"decision","id":"d1","topic":"b","status":"Active","date":"2026-06-25","title":"b"}',
  ]);
  expect(bun([INTEG, dupId]).out).toContain("duplicate index id");
  const malformed = mktmp();
  mkdirSync(join(malformed, ".iroha"), { recursive: true });
  writeFileSync(
    join(malformed, ".iroha", "index.ndjson"),
    '{"type":"decision","id":"d1","topic":"x","status":"Active","date":"2026-06-24","title":"x"}\n{"type":"decision"\n',
  );
  expect(bun([INTEG, malformed]).out).toContain("malformed index line");
  const dangState = intRoot(
    [
      SESSROW.replace(
        "38a822c6-938a-811e-b58a-d62cc504920a",
        "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      ),
    ],
    [
      "**Latest:** x.",
      "## Recent sessions",
      "- [y](https://www.notion.so/ffffffffffffffffffffffffffffffff)",
      "## Decisions",
      "- [DB](u)",
    ].join("\n"),
  );
  expect(bun([INTEG, dangState]).out).toContain(
    "State ahead of saved sessions",
  );
});
test("integrity — the project's REAL committed substrate is clean", () => {
  expect(bun([INTEG, ROOT]).code).toBe(0);
});

// ── state-lint ─────────────────────────────────────────────────────────────────────────────────
test("state-lint (escapes, missing sections, summary, real mirror)", () => {
  const dir = mktmp();
  const good = join(dir, "good.md");
  writeFileSync(
    good,
    [
      "**Latest (2026-06-25):** did things.",
      "## Recent sessions",
      "- [x — y](u)",
      "## Unfinished / Next",
      "- [ ] thing",
      "## Decisions",
      "- [Decisions DB](u)",
      "",
    ].join("\n"),
  );
  expect(bun([STATELINT, good]).code).toBe(0);
  const escapeMd = join(dir, "escapeMd.md");
  writeFileSync(
    escapeMd,
    "**Latest:** a\\nb\\t## Recent sessions\\n## Unfinished\\n## Decisions",
  );
  expect(bun([STATELINT, escapeMd]).code).toBe(1);
  expect(bun([STATELINT, escapeMd]).out).toContain("escape sequence");
  const summaryonly = join(dir, "summaryonly.md");
  writeFileSync(summaryonly, "**Latest:** only a summary, no sections\n");
  expect(bun([STATELINT, summaryonly]).code).toBe(1);
  const empty = join(dir, "empty.md");
  writeFileSync(empty, "");
  expect(bun([STATELINT, empty]).code).toBe(1);
  const mirror = join(ROOT, ".iroha", "state.md");
  if (existsSync(mirror)) expect(bun([STATELINT, mirror]).code).toBe(0); // real mirror is clean when present
});

// ── session-lint ─────────────────────────────────────────────────────────────────────────────────
test("session-lint (escapes, missing/reordered sections, header, optional sections)", () => {
  const dir = mktmp();
  const goodLines = [
    '<callout color="blue_bg">一行サマリ</callout>',
    "## Metrics",
    '<callout color="gray_bg">Duration 10 min · 2 prompts</callout>',
    "## Architecture", // optional — allowed between Metrics and Decisions
    "diagram",
    "## Decisions",
    "| Decision | Why | Rejected |",
    "## Progress",
    "- [x] done",
    "## Highlights",
    "<details><summary>Highlights (2 exchanges)</summary></details>",
    "## Failures", // optional — allowed between Highlights and Details
    "none",
    "## Details",
    "<details><summary>Changed files</summary></details>",
    "",
  ];
  const good = join(dir, "good.md");
  writeFileSync(good, goodLines.join("\n"));
  expect(bun([SESSIONLINT, good]).code).toBe(0);
  // missing a required section (drop Progress)
  const missing = join(dir, "missing.md");
  writeFileSync(
    missing,
    goodLines.filter((l) => l !== "## Progress").join("\n"),
  );
  expect(bun([SESSIONLINT, missing]).code).toBe(1);
  expect(bun([SESSIONLINT, missing]).out).toContain("missing");
  // reordered (Decisions before Metrics)
  const reordered = join(dir, "reordered.md");
  writeFileSync(
    reordered,
    "header\n## Decisions\nx\n## Metrics\ny\n## Progress\nz\n## Highlights\nh\n## Details\nd\n",
  );
  expect(bun([SESSIONLINT, reordered]).code).toBe(1);
  expect(bun([SESSIONLINT, reordered]).out).toContain("appears before");
  // literal escape leak
  const escapeMd = join(dir, "escapeMd.md");
  writeFileSync(
    escapeMd,
    "header\\n## Metrics\\n## Decisions\\n## Progress\\n## Highlights\\n## Details",
  );
  expect(bun([SESSIONLINT, escapeMd]).code).toBe(1);
  expect(bun([SESSIONLINT, escapeMd]).out).toContain("escape sequence");
  // no header content before the first heading
  const noheader = join(dir, "noheader.md");
  writeFileSync(noheader, goodLines.slice(1).join("\n"));
  expect(bun([SESSIONLINT, noheader]).code).toBe(1);
  expect(bun([SESSIONLINT, noheader]).out).toContain("header");
  // empty
  const empty = join(dir, "empty.md");
  writeFileSync(empty, "");
  expect(bun([SESSIONLINT, empty]).code).toBe(1);
});

// ── link-lint ──────────────────────────────────────────────────────────────────────────────────
test("link-lint (bare file/path tokens outside backticks/fences/links)", () => {
  const ll = (md: string) => bun([LINKLINT], { input: md });
  expect(ll("save が extract.sh を呼ぶ\n").code).toBe(1);
  expect(ll("save が extract.sh を呼ぶ\n").err).toContain("extract.sh"); // offenders -> stderr
  expect(ll("save が `extract.sh` を呼ぶ\n").code).toBe(0);
  expect(ll("```\nextract.sh all\n```\nplain\n").code).toBe(0);
  expect(ll("[State](https://app.notion.com/p/abc123)\n").code).toBe(0);
  expect(ll("v0.2.0 をリリース。総合70/100。Node20警告。\n").code).toBe(0);
});
