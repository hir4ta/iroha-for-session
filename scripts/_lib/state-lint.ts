// state-lint.ts — validate a State body BEFORE it is published to Notion / committed.
//
// Under save-session §8's single-source rule, the repo mirror <root>/.iroha/state.md is written
// ONCE and the byte-identical text is published to the Notion State page — so linting the mirror
// also validates what Notion will render. This catches the State-corruption class found while
// dogfooding (a save left the Notion State as a summary-only callout with literal \n / \t escapes
// leaking in), turning the most defect-prone write surface from "detect after the fact (audit)"
// into "prevent before write": run it in save-session before publishing, in audit as the
// deterministic escape/section check, and in selftest against the real committed mirror so a
// corrupt State can never reach CI green.
//
// Checks are LANGUAGE-INDEPENDENT (structure only — no dependence on translated heading text):
//   1. non-empty file.
//   2. no literal "\n" / "\t" two-character escape sequences — the body must contain REAL
//      newlines/tabs; the escaped form is exactly the leak that degraded a past State.
//   3. >= 3 "## " section headings — a State that degraded to a summary-only callout loses the
//      Recent-sessions / Unfinished / Decisions sections it exists to provide.
//   4. a summary line before the first "## " heading (the "**Latest (...)**" one-liner).

import { existsSync, readFileSync, statSync } from "node:fs";

// stateLint(file) -> issue strings (empty list = clean).
export function stateLint(file: string): string[] {
  const issues: string[] = [];
  if (!existsSync(file) || statSync(file).size === 0) {
    return [`state-lint: missing or empty file: ${file}`];
  }
  const body = readFileSync(file, "utf8");
  // Literal backslash-n / backslash-t (the two-character escape leak), not real newlines/tabs.
  if (body.includes("\\n") || body.includes("\\t")) {
    issues.push(
      "state-lint: literal \\n or \\t escape sequence found — State must contain real newlines/tabs",
    );
  }
  const lines = body.split("\n");
  const headings = lines.filter((l) => /^## /.test(l)).length;
  if (headings < 3) {
    issues.push(
      `state-lint: only ${headings} '## ' sections (need >= 3: Recent sessions / Unfinished / Decisions) — State may have degraded to a summary`,
    );
  }
  // Is there a non-blank line before the first '## ' heading (the "**Latest (...)**" summary)?
  let summaryFound = false;
  for (const l of lines) {
    if (/^## /.test(l)) break;
    if (/\S/.test(l)) summaryFound = true;
  }
  if (!summaryFound) {
    issues.push("state-lint: no summary line before the first '## ' heading");
  }
  return issues;
}

// CLI: usable from skills as `bun state-lint.ts <state.md>`. Guarded so importing is a no-op.
if (import.meta.main) {
  const issues = stateLint(process.argv[2] ?? "");
  for (const line of issues) console.log(line);
  process.exit(issues.length === 0 ? 0 : 1);
}
