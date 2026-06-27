// session-lint.ts — validate a composed Session page body BEFORE it is published to Notion.
//
// save-session §5 prescribes a fixed section structure: the always-present sections Metrics /
// Decisions / Progress / Highlights / Details (in that order), with optional Architecture / Rules
// changed / Failures interleaved at their canonical positions. That structure is what recall, audit,
// and a human reader rely on — but until now nothing checked it before the write: a drifted body (a
// missing section, a reordered one, or a literal \n / \t escape leak) would publish silently and
// quietly degrade the "living memory". This is the Session-page analogue of state-lint — it turns
// structural drift from "detect after the fact (audit)" into "prevent before write". save-session
// already writes the composed content to a temp file for link-lint; run this on the same file, and
// the bun-test oracle runs it against good/bad bodies so a corrupt structure can't reach CI green.
//
// Checks are STRUCTURAL and LANGUAGE-INDEPENDENT (the section headings are English canonical by
// design — save-session keeps them verbatim and localizes only the body prose). It validates the
// skeleton, NOT semantics: it cannot catch a fabricated Highlight (that is the LLM's job, anchored
// to the deterministic prompts/chat extracts) — exactly the boundary state-lint also stops at.
//   1. non-empty file.
//   2. no literal "\n" / "\t" two-character escape sequence — the body must contain REAL
//      newlines/tabs (the same leak state-lint guards).
//   3. every REQUIRED "## " section present: Metrics, Decisions, Progress, Highlights, Details.
//   4. the required sections appear in canonical order (optional sections may sit between them).
//   5. header content before the first "## " heading (the one-line summary callout).

import { existsSync, readFileSync, statSync } from "node:fs";

// The always-present sections, in canonical order (save-session §5). Optional sections
// (Architecture / Rules changed / Failures) are allowed but not required, so they are not listed.
const REQUIRED_SECTIONS = [
  "Metrics",
  "Decisions",
  "Progress",
  "Highlights",
  "Details",
];

// sessionLint(file) -> issue strings (empty list = clean).
export function sessionLint(file: string): string[] {
  const issues: string[] = [];
  if (!existsSync(file) || statSync(file).size === 0) {
    return [`session-lint: missing or empty file: ${file}`];
  }
  const body = readFileSync(file, "utf8");
  // Literal backslash-n / backslash-t (the two-character escape leak), not real newlines/tabs.
  if (body.includes("\\n") || body.includes("\\t")) {
    issues.push(
      "session-lint: literal \\n or \\t escape sequence found — body must contain real newlines/tabs",
    );
  }
  const lines = body.split("\n");
  // First "## <Section>" line index per required section (-1 = absent). Word boundary so a heading
  // with trailing text still counts but a different heading (## DecisionsFoo) does not.
  const sections = REQUIRED_SECTIONS.map((name) => ({
    name,
    idx: lines.findIndex((l) => new RegExp(`^##\\s+${name}\\b`).test(l)),
  }));

  const missing = sections.filter((s) => s.idx < 0).map((s) => s.name);
  if (missing.length > 0) {
    issues.push(
      `session-lint: missing required '## ' section(s): ${missing.join(", ")} (canonical order: ${REQUIRED_SECTIONS.join(" -> ")})`,
    );
  }

  // Order check over the sections that ARE present (a missing one is already reported above).
  const present = sections.filter((s) => s.idx >= 0);
  for (let i = 1; i < present.length; i++) {
    const cur = present[i];
    const prev = present[i - 1];
    if (cur && prev && cur.idx < prev.idx) {
      issues.push(
        `session-lint: section '${cur.name}' appears before '${prev.name}' — canonical order is ${REQUIRED_SECTIONS.join(" -> ")}`,
      );
      break;
    }
  }

  // Is there a non-blank line before the first '## ' heading (the blue_bg one-line summary callout)?
  let headerFound = false;
  for (const l of lines) {
    if (/^## /.test(l)) break;
    if (/\S/.test(l)) headerFound = true;
  }
  if (!headerFound) {
    issues.push(
      "session-lint: no header/summary content before the first '## ' heading",
    );
  }
  return issues;
}

// CLI: usable from skills as `bun session-lint.ts <session.md>`. Guarded so importing is a no-op.
if (import.meta.main) {
  const issues = sessionLint(process.argv[2] ?? "");
  for (const line of issues) console.log(line);
  process.exit(issues.length === 0 ? 0 : 1);
}
