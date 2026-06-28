// Behavioral oracle for compose-session.ts — the deterministic Session-body renderer. Asserts the
// body is lint-clean BY CONSTRUCTION (passes session-lint + link-lint), emits the canonical sections
// in order, builds Metrics verbatim from stats, auto-backticks bare file/path tokens, and includes
// optional sections only when present. Imports render() in-process; runs the CLI once end-to-end.
import { expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { linkLint } from "../scripts/_lib/link-lint.ts";
import { sessionLint } from "../scripts/_lib/session-lint.ts";
import {
  backtickTokens,
  type Extract,
  type Intel,
  render,
} from "../scripts/compose-session.ts";

const ROOT = join(import.meta.dir, "..");
const COMPOSE = join(ROOT, "scripts/compose-session.ts");
const mktmp = () => mkdtempSync(join(tmpdir(), "iroha-compose."));

const EX: Extract = {
  stats: {
    userTurns: 3,
    assistantTurns: 74,
    toolCalls: 144,
    filesEdited: 20,
    bashCommands: 46,
    durationMin: 67,
  },
  files: [
    "- `scripts/compose-session.ts` (write)",
    "- `skills/save-session/SKILL.md` (edit)",
  ],
  commands: ["- `bun test`", "- `bunx tsc --noEmit`"],
  tools: ["- `Edit` ×12", "- `Bash` ×46"],
};

const INTEL: Intel = {
  summary: "save の機械化として compose-session.ts を新設",
  architecture: {
    caption: "save のデータフロー",
    mermaid: "graph TD\n  A[extract] --> B[compose] --> C[Notion]",
  },
  decisions: [
    {
      decision: "Notion: MCP only",
      why: "extract.ts の出力を compose で使い配布を単一セットアップに保つ",
      rejected: "API トークン直書き (二重セットアップ)",
    },
  ],
  done: ["compose-session.ts を実装", "session-lint の誤検知を修正"],
  unfinished: ["State 本文の描画は後回し"],
  rulesChanged: ["save は intel JSON を出して compose-session.ts に渡す"],
  failures: [
    {
      symptom: "lint 目視往復",
      cause: "手組み Markdown",
      fix: "決定論レンダラ",
    },
  ],
  highlights: [
    { who: "You", text: "前回の続きからやりたい" },
    { who: "Claude", text: "compose スクリプトへ寄せる方向を提案" },
  ],
};

// ── lint-clean by construction ───────────────────────────────────────────────────────────────────
test("render output passes session-lint and link-lint", () => {
  const dir = mktmp();
  const body = render(INTEL, EX);
  const f = join(dir, "body.md");
  writeFileSync(f, body);
  expect(sessionLint(f)).toEqual([]);
  expect(linkLint(body)).toEqual([]);
  // real tabs/newlines, never the two-char escape leak.
  expect(body).not.toContain("\\n");
  expect(body.includes("\t")).toBe(true);
});

// ── canonical sections in order ──────────────────────────────────────────────────────────────────
test("required sections appear in canonical order", () => {
  const body = render(INTEL, EX);
  const order = [
    "## Metrics",
    "## Decisions",
    "## Progress",
    "## Highlights",
    "## Details",
  ];
  let prev = -1;
  for (const h of order) {
    const idx = body.indexOf(h);
    expect(idx).toBeGreaterThan(prev);
    prev = idx;
  }
  // header callout precedes the first heading
  expect(body.indexOf('<callout color="blue_bg">')).toBeLessThan(
    body.indexOf("## Metrics"),
  );
});

// ── Metrics built verbatim from stats ────────────────────────────────────────────────────────────
test("Metrics dashboard is built from stats, not hand-counted", () => {
  const body = render(INTEL, EX);
  expect(body).toContain(
    "Duration 67 min · 3 prompts → 74 Claude replies · 144 tool calls (46 bash) · 20 files changed",
  );
});

// ── optional sections + highlights ───────────────────────────────────────────────────────────────
test("optional sections render when present; highlights carry count + speaker colors", () => {
  const body = render(INTEL, EX);
  expect(body).toContain("## Architecture");
  expect(body).toContain("```mermaid");
  expect(body).toContain("## Rules changed");
  expect(body).toContain("## Failures");
  expect(body).toContain("<summary>Highlights (2 exchanges)</summary>");
  expect(body).toContain('<callout color="blue_bg">\n\t\t**You**');
  expect(body).toContain('<callout color="gray_bg">\n\t\t**Claude**');
  // decisions render as a table with the canonical column header row
  expect(body).toContain('<table header-row="true">');
  expect(body).toContain("<td>Decision</td>");
});

test("optional sections are omitted when empty; required sections still present + clean", () => {
  const dir = mktmp();
  const minimal: Intel = {
    summary: "最小セッション",
    done: ["何かした"],
    unfinished: [],
    highlights: [],
  };
  const body = render(minimal, EX);
  expect(body).not.toContain("## Architecture");
  expect(body).not.toContain("## Rules changed");
  expect(body).not.toContain("## Failures");
  // no decisions -> placeholder callout, not an empty table
  expect(body).toContain("No architecture-shaping decisions this session.");
  expect(body).not.toContain("<table");
  const f = join(dir, "min.md");
  writeFileSync(f, body);
  expect(sessionLint(f)).toEqual([]);
  expect(linkLint(body)).toEqual([]);
});

// ── auto-backtick (the deterministic link-lint fix) ──────────────────────────────────────────────
test("bare file/path tokens in prose are auto-backticked", () => {
  const body = render(INTEL, EX);
  // the decision 'why' mentioned extract.ts bare; the renderer wraps it
  expect(body).toContain("`extract.ts`");
});

test("backtickTokens wraps bare tokens, leaves code spans and links untouched", () => {
  expect(backtickTokens("call extract.ts now")).toBe("call `extract.ts` now");
  expect(backtickTokens("already `extract.ts` here")).toBe(
    "already `extract.ts` here",
  );
  expect(backtickTokens("[State](https://app.notion.com/a.ts)")).toBe(
    "[State](https://app.notion.com/a.ts)",
  );
  expect(backtickTokens("plain prose, no tokens")).toBe(
    "plain prose, no tokens",
  );
});

// ── Notion tag escaping (structure-safe content; no table/callout corruption or markup injection) ──
test("tag chars < > in prose/cells are escaped; structural tags stay raw; still lint-clean", () => {
  const intel: Intel = {
    summary: "比較演算子 a < b と JSX <Foo/> を含む要約",
    decisions: [
      {
        decision: "Generic<T> を導入",
        why: "型安全",
        rejected: "any 型で <td>ベタ書き</td>",
      },
    ],
    done: [],
    unfinished: [],
    highlights: [],
  };
  const body = render(intel, EX);
  // CONTENT `<`/`>` are escaped, so a literal `<td>`/`</td>`/JSX cannot open a Notion tag
  expect(body).toContain("Generic\\<T\\>");
  expect(body).toContain("\\<td\\>");
  expect(body).not.toContain("any 型で <td>"); // the raw, table-breaking form is gone
  expect(body).toContain("a \\< b");
  // STRUCTURAL tags the renderer itself emits are untouched (only content is escaped)
  expect(body).toContain("<td>Decision</td>");
  expect(body).toContain('<table header-row="true">');
  // and the escaped body is still lint-clean by construction
  const f = join(mktmp(), "esc.md");
  writeFileSync(f, body);
  expect(sessionLint(f)).toEqual([]);
  expect(linkLint(body)).toEqual([]);
});

// ── PR link (Session↔PR) — optional, deterministic, lint-clean, omitted when absent ──────────────
test("PR link renders OPEN-first when prs are passed; absent when none; stays lint-clean", () => {
  // render takes prs already sorted (gh.ts sorts OPEN-first); pass in that order.
  const ordered = [
    {
      number: 7,
      url: "https://github.com/o/r/pull/7",
      title: "feat: shiny",
      state: "open",
    },
    {
      number: 3,
      url: "https://github.com/o/r/pull/3",
      title: "old",
      state: "merged",
    },
  ];
  const body = render(INTEL, EX, ordered);
  expect(body).toContain(
    "**PR:** [#7 feat: shiny](https://github.com/o/r/pull/7) (open)",
  );
  expect(body).toContain("[#3 old](https://github.com/o/r/pull/3) (merged)");
  // the PR line sits between Metrics and the next section, and the body stays lint-clean
  expect(body.indexOf("**PR:**")).toBeGreaterThan(body.indexOf("## Metrics"));
  expect(body.indexOf("**PR:**")).toBeLessThan(body.indexOf("## Decisions"));
  const f = join(mktmp(), "pr.md");
  writeFileSync(f, body);
  expect(sessionLint(f)).toEqual([]);
  expect(linkLint(body)).toEqual([]);
  // no prs -> no PR line (backward compatible)
  expect(render(INTEL, EX)).not.toContain("**PR:**");
});

// ── CLI end-to-end (self-lint + file write + stdout path) ────────────────────────────────────────
test("CLI renders to the out file, self-lints clean, prints the path", () => {
  const dir = mktmp();
  const intelPath = join(dir, "intel.json");
  const extractPath = join(dir, "extract.json");
  const outPath = join(dir, "out.md");
  writeFileSync(intelPath, JSON.stringify(INTEL));
  // a real extract.ts `all` carries meta/prompts/chat too; the renderer only reads stats/files/…
  writeFileSync(
    extractPath,
    JSON.stringify({ ...EX, meta: {}, prompts: [], chat: [] }),
  );
  const r = spawnSync("bun", [COMPOSE, intelPath, extractPath, outPath], {
    encoding: "utf8",
  });
  expect(r.status).toBe(0);
  expect(r.stdout.trim()).toBe(outPath);
  const written = readFileSync(outPath, "utf8");
  expect(written).toContain("## Metrics");
  expect(sessionLint(outPath)).toEqual([]);
});
