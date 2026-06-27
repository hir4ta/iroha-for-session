// link-lint.ts — deterministic guard against Notion auto-linkifying bare file/command/path tokens.
//
// Notion turns a bare `foo.sh` / `CLAUDE.md` / `.iroha/state.md` in BODY text into a bogus
// `http://foo.sh` link (it grabs the surrounding run, sometimes a whole sentence). The fix is to
// wrap every file / command / path in backticks — the save / init / project / digest skills all
// say so, but that is human diligence and it recurs every save. This lints the to-be-published
// Markdown and FAILS if a risky token sits OUTSIDE a backtick span / fenced code block / explicit
// [text](url) link, so a leak-prone page is caught BEFORE it reaches Notion — the same gate role
// state-lint.ts plays for the \n/\t leak.
//
// It only flags FILE/PATH-shaped tokens (a token ending in a known code/text extension), which is
// the class Notion mis-linkifies; bare prose and real URLs are left alone to avoid false positives.

import { readFileSync } from "node:fs";

const TOKEN =
  /[A-Za-z0-9._/~+-]+\.(sh|md|json|jsonl|ya?ml|toml|tsx?|jsx?|mjs|cjs|py|go|rs|txt|sql|lock|env|cfg|ini|svg)\b/g;

// linkLint(markdown) -> sorted unique offending tokens (empty list = clean). Processed line-by-line
// (matching the original awk/sed/grep pipeline): fenced code blocks are dropped, then inline code
// spans and [text](url) links are stripped, then file/path-shaped tokens in the remainder are flagged.
export function linkLint(markdown: string): string[] {
  const found = new Set<string>();
  let inFence = false;
  for (const raw of markdown.split("\n")) {
    if (/^[ \t]*```/.test(raw)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    const line = raw
      .replace(/`[^`]*`/g, "")
      .replace(/\[[^\]]*\]\([^)]*\)/g, "");
    for (const m of line.matchAll(TOKEN)) found.add(m[0]);
  }
  return [...found].sort();
}

// CLI: `bun link-lint.ts <file>` or pipe Markdown on stdin. exit 0 = clean; exit 1 = offenders.
if (import.meta.main) {
  const arg = process.argv[2];
  const src =
    arg && arg !== "-" ? readFileSync(arg, "utf8") : readFileSync(0, "utf8");
  const offenders = linkLint(src);
  if (offenders.length > 0) {
    process.stderr.write(
      "link-lint: un-backticked file/path token(s) — Notion will auto-linkify these to http://… ;\n" +
        "wrap each in backticks (or rephrase) and re-lint until clean:\n",
    );
    for (const o of offenders) process.stderr.write(`  ${o}\n`);
    process.exit(1);
  }
  process.exit(0);
}
