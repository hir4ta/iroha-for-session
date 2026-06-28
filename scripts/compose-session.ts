// compose-session.ts — deterministically render a Session page BODY from the intelligence Claude
// composes (summary / decisions / progress / highlights / failures) plus the deterministic
// `extract.ts all` output (stats / files / commands / tools).
//
// save-session §5 prescribes a fixed section structure and a set of leak-prone hand-formatting
// rules: canonical section order, real newlines/tabs (never the two-char \n / \t escape), and every
// bare file/path token backticked so Notion does not auto-linkify it to http://… . Doing all that by
// hand in the skill prompt is the documented source of save's fragility — the link-lint /
// session-lint round-trips and the "machine work pushed onto Claude" feedback. This script makes the
// body LINT-CLEAN BY CONSTRUCTION: sections are always emitted in canonical order with the canonical
// English headings (session-lint passes), the output is real newlines/tabs, and every bare file/path
// token in prose is auto-backticked with the SAME TOKEN regex link-lint flags (link-lint passes).
// Claude composes only the intelligence; the structure is code.
//
// Structural scaffolding (section headings, table column labels, Done/Unfinished/Changed files…
// labels, "Highlights (N exchanges)") stays English canonical — like the `##` headings, it is
// structure, not prose. The BODY CONTENT (summary, decision cells, progress items, highlight text)
// is whatever Claude puts in the JSON, i.e. the user's conversation language.
//
// Read-only except for writing the out file; diagnostics go to stderr. self-lints the result as a
// safety net (a non-clean output is a renderer bug, not the caller's).
//
// Usage: compose-session.ts <intel.json> <extract.json> <out.md>

import { readFileSync, writeFileSync } from "node:fs";
import { linkLint } from "./_lib/link-lint.ts";
import { sessionLint } from "./_lib/session-lint.ts";

// The intelligence JSON Claude composes (step 4 of save-session). Optional sections are omitted /
// empty when they do not apply.
interface Decision {
  decision: string;
  why: string;
  rejected: string;
}
interface Failure {
  symptom: string;
  cause: string;
  fix: string;
}
interface Highlight {
  who: string; // "You" | "Claude" (case-insensitive); anything else renders as Claude.
  text: string;
}
interface Architecture {
  caption: string;
  mermaid: string;
}
export interface Intel {
  summary: string;
  architecture?: Architecture | null;
  decisions?: Decision[];
  done?: string[];
  unfinished?: string[];
  rulesChanged?: string[];
  failures?: Failure[];
  highlights?: Highlight[];
}
// The slice of `extract.ts all` the body needs (stats dashboard + the verbatim, already-backticked
// `- ` lists). meta/prompts/chat are used elsewhere in the skill, not in the body.
interface Stats {
  userTurns: number;
  assistantTurns: number;
  toolCalls: number;
  filesEdited: number;
  bashCommands: number;
  durationMin: number;
}
export interface Extract {
  stats: Stats;
  files: string[];
  commands: string[];
  tools: string[];
}

// link-lint's file/path token class — the tokens Notion mis-linkifies to http://… .
const TOKEN =
  /[A-Za-z0-9._/~+-]+\.(sh|md|json|jsonl|ya?ml|toml|tsx?|jsx?|mjs|cjs|py|go|rs|txt|sql|lock|env|cfg|ini|svg)\b/g;
// Spans link-lint already leaves alone: an inline `code` span or an explicit [text](url) link.
const PROTECT = /(`[^`]*`|\[[^\]]*\]\([^)]*\))/;

// Wrap every bare file/path token in backticks, but leave tokens already inside a code span or a
// link untouched (so we never double-wrap or break a link) — the deterministic, by-construction
// version of the link-lint gate the skill used to run by hand. split() with PROTECT's single
// capture group yields [plain, protected, plain, …]; only the plain (even) segments are rewritten.
export function backtickTokens(text: string): string {
  return text
    .split("\n")
    .map((line) =>
      line
        .split(PROTECT)
        .map((seg, i) => (i % 2 === 1 ? seg : seg.replace(TOKEN, "`$&`")))
        .join(""),
    )
    .join("\n");
}

// Collapse internal whitespace to single spaces — table cells and callout one-liners are rich text
// and must not carry block newlines that would break the <table> / <callout>.
function oneLine(s: string): string {
  return String(s ?? "")
    .replace(/\s+/g, " ")
    .trim();
}
// A table cell: single line, file/path tokens backticked.
function cell(s: string): string {
  return backtickTokens(oneLine(s));
}
// A prose line (kept as-is except auto-backticking) for list items / callout text.
function prose(s: string): string {
  return backtickTokens(oneLine(s));
}

export function render(intel: Intel, ex: Extract): string {
  const out: string[] = [];
  const push = (s = "") => out.push(s);

  // Header — blue_bg callout with the one-line summary. MUST precede the first `## ` (session-lint
  // requires header content before the first heading); the page properties already show
  // Project/Status/Type/Date, so no meta table here.
  push('<callout color="blue_bg">');
  push(`\t${prose(intel.summary)}`);
  push("</callout>");
  push();

  // ## Metrics — dashboard built verbatim from stats (never hand-counted).
  const s = ex.stats;
  push("## Metrics");
  push();
  push('<callout color="gray_bg">');
  push(
    `\tDuration ${s.durationMin} min · ${s.userTurns} prompts → ${s.assistantTurns} Claude replies · ${s.toolCalls} tool calls (${s.bashCommands} bash) · ${s.filesEdited} files changed`,
  );
  push("</callout>");
  push();

  // ## Architecture (optional) — caption first (so a reader never asks "a diagram of what?"), then
  // the mermaid block verbatim (no escaping, no auto-backtick inside a code fence).
  const arch = intel.architecture;
  if (arch && oneLine(arch.mermaid) !== "") {
    push("## Architecture");
    push();
    if (oneLine(arch.caption) !== "") {
      push(prose(arch.caption));
      push();
    }
    push("```mermaid");
    push(arch.mermaid.replace(/\n+$/, ""));
    push("```");
    push();
  }

  // ## Decisions — session-level decisions table (broader than the Decisions DB).
  push("## Decisions");
  push();
  const decisions = intel.decisions ?? [];
  if (decisions.length === 0) {
    push('<callout color="gray_bg">');
    push("\tNo architecture-shaping decisions this session.");
    push("</callout>");
  } else {
    push('<table header-row="true">');
    push('\t<tr color="blue_bg">');
    push("\t\t<td>Decision</td>");
    push("\t\t<td>Why</td>");
    push("\t\t<td>Rejected alternatives</td>");
    push("\t</tr>");
    for (const d of decisions) {
      push("\t<tr>");
      push(`\t\t<td>${cell(d.decision)}</td>`);
      push(`\t\t<td>${cell(d.why)}</td>`);
      push(`\t\t<td>${cell(d.rejected)}</td>`);
      push("\t</tr>");
    }
    push("</table>");
  }
  push();

  // ## Progress — Done (green) + Unfinished / Next (orange checklist).
  push("## Progress");
  push();
  push('<callout color="green_bg">');
  push("\t**Done**");
  const done = intel.done ?? [];
  if (done.length === 0) push("\t- (none)");
  else for (const it of done) push(`\t- ${prose(it)}`);
  push("</callout>");
  push();
  push('<callout color="orange_bg">');
  push("\t**Unfinished / Next**");
  const un = intel.unfinished ?? [];
  if (un.length === 0) push("\t- (none)");
  else for (const it of un) push(`\t- [ ] ${prose(it)}`);
  push("</callout>");
  push();

  // ## Highlights — alternating chat-style callouts in a collapsed toggle. The You text is the
  // human's real words (Claude anchors it to the prompts extract); Claude lines are paraphrased.
  const hl = intel.highlights ?? [];
  push("## Highlights");
  push();
  push("<details>");
  push(`<summary>Highlights (${hl.length} exchanges)</summary>`);
  for (const h of hl) {
    const you = /^you$/i.test(String(h.who ?? ""));
    push(`\t<callout color="${you ? "blue_bg" : "gray_bg"}">`);
    push(`\t\t**${you ? "You" : "Claude"}** ${prose(h.text)}`);
    push("\t</callout>");
  }
  push("</details>");
  push();

  // ## Rules changed (optional) — only rules newly established/changed this session.
  const rules = intel.rulesChanged ?? [];
  if (rules.length > 0) {
    push("## Rules changed");
    push();
    push('<callout color="gray_bg">');
    for (const r of rules) push(`\t- ${prose(r)}`);
    push("</callout>");
    push();
  }

  // ## Failures (optional) — symptom → root cause → fix, in a collapsed toggle (Reflexion).
  const fails = intel.failures ?? [];
  if (fails.length > 0) {
    push("## Failures");
    push();
    push("<details>");
    push(`<summary>Failures (${fails.length})</summary>`);
    for (const f of fails)
      push(`\t- ${prose(f.symptom)} → ${prose(f.cause)} → ${prose(f.fix)}`);
    push("</details>");
    push();
  }

  // ## Details — Changed files / Commands / Tools, each a toggle; lists are the verbatim,
  // already-backticked `- ` lines from extract.ts (tab-indented to nest under the toggle).
  push("## Details");
  push();
  detailsToggle(out, `Changed files (${ex.files.length})`, ex.files);
  push();
  detailsToggle(out, `Commands (${ex.commands.length})`, ex.commands);
  push();
  detailsToggle(out, "Tools", ex.tools);

  return `${out.join("\n")}\n`;
}

// A <details> toggle wrapping verbatim `- ` list lines (already backticked by extract.ts).
function detailsToggle(out: string[], summary: string, items: string[]): void {
  out.push("<details>");
  out.push(`<summary>${summary}</summary>`);
  if (items.length === 0) out.push("\t- (none)");
  else for (const it of items) out.push(`\t${it}`);
  out.push("</details>");
}

if (import.meta.main) {
  const [intelPath, extractPath, outPath] = process.argv.slice(2);
  if (!intelPath || !extractPath || !outPath) {
    process.stderr.write(
      "usage: compose-session.ts <intel.json> <extract.json> <out.md>\n",
    );
    process.exit(2);
  }
  const intel = JSON.parse(readFileSync(intelPath, "utf8")) as Intel;
  const ex = JSON.parse(readFileSync(extractPath, "utf8")) as Extract;
  const body = render(intel, ex);
  writeFileSync(outPath, body);

  // Safety net: the body is lint-clean by construction. If either lint fires, that is a renderer
  // bug — fail loudly rather than publish a body the skill would otherwise have to hand-fix.
  const sIssues = sessionLint(outPath);
  const lIssues = linkLint(body).map(
    (o) => `link-lint: un-backticked token: ${o}`,
  );
  if (sIssues.length > 0 || lIssues.length > 0) {
    process.stderr.write(
      "compose-session: internal lint failure (renderer bug, please report):\n",
    );
    for (const m of [...sIssues, ...lIssues]) process.stderr.write(`  ${m}\n`);
    process.exit(1);
  }
  process.stdout.write(`${outPath}\n`);
  process.exit(0);
}
