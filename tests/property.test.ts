// property.test.ts — property-based invariants (fast-check) for the deterministic publish/parse gates.
//
// The fixture-based oracle (lib.test.ts / hooks.test.ts) checks specific inputs; this checks the
// INVARIANTS over a generated space of inputs, where edge cases (the `+ ~ -` chars TOKEN allows,
// multibyte text, truncated JSONL) hide. Two gates earn property coverage:
//   - link-lint.ts: the auto-linkify guard. Its contract is purely structural, so it is a natural
//     fit — a backticked / fenced / linked token must NEVER flag, a bare file token must ALWAYS flag,
//     and the output is always sorted + deduped.
//   - extract.ts parseRecords: a transcript can be truncated (crash mid-line), so parsing must be
//     non-fatal — every malformed line skipped, every valid object line kept, never throwing.

import { expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import fc from "fast-check";
import { linkLint } from "../scripts/_lib/link-lint.ts";
import { parseRecords } from "../scripts/extract.ts";

// A file/path-shaped token: a basename over the chars TOKEN allows (minus `.` `/` so the token has
// exactly one extension), plus a known extension. This exercises the tricky `_ + ~ -` chars.
const EXT = [
  "sh",
  "md",
  "json",
  "jsonl",
  "yaml",
  "yml",
  "toml",
  "ts",
  "tsx",
  "js",
  "jsx",
  "mjs",
  "cjs",
  "py",
  "go",
  "rs",
  "txt",
  "sql",
  "lock",
  "env",
  "cfg",
  "ini",
  "svg",
];
const baseChar = fc.constantFrom(
  ..."abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+~-".split(
    "",
  ),
);
const fileToken = fc
  .tuple(
    fc.array(baseChar, { minLength: 1, maxLength: 24 }).map((a) => a.join("")),
    fc.constantFrom(...EXT),
  )
  .map(([base, ext]) => `${base}.${ext}`);

test("link-lint: a backticked file token is NEVER flagged", () => {
  fc.assert(
    fc.property(
      fileToken,
      (t) => !linkLint(`これは \`${t}\` です`).includes(t),
    ),
  );
});

test("link-lint: a bare file token is ALWAYS flagged", () => {
  fc.assert(
    fc.property(fileToken, (t) => linkLint(`これは ${t} です`).includes(t)),
  );
});

test("link-lint: a file token inside a fenced code block is NEVER flagged", () => {
  fc.assert(
    fc.property(
      fileToken,
      (t) => linkLint(`\`\`\`\n${t}\n\`\`\``).length === 0,
    ),
  );
});

test("link-lint: a file token inside a [text](url) link is NEVER flagged", () => {
  fc.assert(
    fc.property(fileToken, (t) => !linkLint(`[見出し](${t})`).includes(t)),
  );
});

test("link-lint: output is always sorted and deduplicated", () => {
  fc.assert(
    fc.property(fc.array(fileToken, { maxLength: 12 }), (tokens) => {
      const out = linkLint(tokens.join(" "));
      const unique = new Set(out).size === out.length;
      const sorted = [...out].every(
        (v, i) => i === 0 || (out[i - 1] as string) <= v,
      );
      return unique && sorted;
    }),
  );
});

// A line guaranteed NOT to be valid JSON (and single-line) — the "truncated / garbage" case.
const garbageLine = fc
  .string({ minLength: 1 })
  .map((s) => s.replace(/[\n\r]/g, " "))
  .filter((s) => {
    if (s.trim() === "") return false;
    try {
      JSON.parse(s);
      return false; // happened to be valid JSON — exclude from the "garbage" pool
    } catch {
      return true;
    }
  });
// A valid record line: JSON.stringify of an object always parses back to one record.
const recordLine = fc
  .record({
    type: fc.constantFrom("user", "assistant", "system"),
    n: fc.integer(),
  })
  .map((o) => JSON.stringify(o));

test("extract.parseRecords: never throws; keeps valid lines, skips garbage", () => {
  fc.assert(
    fc.property(
      fc.array(fc.oneof(recordLine, garbageLine, fc.constant("")), {
        maxLength: 40,
      }),
      (lines) => {
        const dir = mkdtempSync(join(tmpdir(), "iroha-prop-"));
        try {
          const f = join(dir, "t.jsonl");
          writeFileSync(f, lines.join("\n"));
          const recs = parseRecords(f);
          // Every valid JSON-object line is kept; blank + garbage lines are skipped, never fatal.
          const validCount = lines.filter((l) => {
            if (l.trim() === "") return false;
            try {
              JSON.parse(l);
              return true;
            } catch {
              return false;
            }
          }).length;
          return recs.length === validCount;
        } finally {
          rmSync(dir, { recursive: true, force: true });
        }
      },
    ),
    { numRuns: 50 },
  );
});

// A trivial assertion so the file reads as a normal test too (and `expect` import is used).
test("fast-check is wired into the bun-test oracle", () => {
  expect(typeof fc.assert).toBe("function");
});
