// recall-eval.ts — quality oracle for the local recall stage (scripts/_lib/search.ts).
//
// selftest proves the search MECHANICS (tokenization, status weight, abstention) on synthetic
// fixtures. This proves the search QUALITY on a frozen snapshot of a real index: a hand-labeled
// golden set of realistic developer prompts paired with the decision/session they should surface,
// plus abstention prompts that must surface nothing. It reports Recall@k, MRR, and abstention
// accuracy, and exits non-zero if they fall below threshold.
//
// It runs against a FROZEN fixture corpus (tests/fixtures/recall-corpus/.iroha/index.ndjson), NOT
// the live repo index — so a workspace re-save / re-init churning decision ids never breaks CI (that
// drift red-failed CI three times). The fixture is a snapshot of a real index; regenerate it
// DELIBERATELY (`cp .iroha/index.ndjson tests/fixtures/recall-corpus/.iroha/`) and re-label the
// golden only when you actually want to change the test corpus, never as forced re-save fallout.
// Pass an explicit <root> arg to eval a different index ad-hoc. Run: bun tests/recall-eval.ts; echo $?
//
// KNOWN LIMITATION (abstention is scoped, not absolute). The negatives here are CROSS-DOMAIN
// (different language AND topic), which a pure-lexical pass abstains on cleanly. An off-topic prompt
// that shares the corpus's *software* vocabulary can clear the floor and leak a hit — an inherent
// limit of lexical recall on a small, single-domain corpus. The fix is the deep /iroha:recall
// semantic stage (Notion's own search), not a raised floor (that would trade away recall).

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { search } from "../scripts/_lib/search.ts";

const out = (s: string) => process.stdout.write(`${s}\n`);

const ROOT =
  process.argv[2] ?? join(import.meta.dir, "fixtures", "recall-corpus");
const K = 3; // Recall@K — how many hits the hook would surface
const MINSCORE = Number(process.env.IROHA_RECALL_MINSCORE ?? "1.2"); // production floor
const RECALL_THRESHOLD = 80; // require Recall@K >= 80%
const ABSTAIN_THRESHOLD = 100; // require 100% honest abstention

// Golden set: tests/golden-recall.txt.
const golden = readFileSync(join(import.meta.dir, "golden-recall.txt"), "utf8")
  .split("\n")
  .map((l) => l.trim())
  .filter((l) => l !== "" && !l.startsWith("#"));

let posTotal = 0;
let posHit = 0;
let mrrSum = 0;
let absTotal = 0;
let absOk = 0;

out(
  `=== recall-eval (Recall@${K}, MINSCORE=${MINSCORE}) over ${ROOT}/.iroha/index.ndjson ===`,
);
out(`${"query".padEnd(52)} ${"result".padEnd(8)} rank/expected`);

for (const line of golden) {
  const [query, expect] = line.split("|");
  if (!query || expect === undefined) continue;
  const ids = search(ROOT, query, "", K, MINSCORE).map((h) => h.id);
  const q = query.slice(0, 50).padEnd(52);
  if (expect === "NONE") {
    absTotal += 1;
    if (ids.length === 0) {
      absOk += 1;
      out(`${q} ${"ABSTAIN".padEnd(8)} ok (no hit)`);
    } else {
      out(`${q} ${"LEAK".padEnd(8)} got ${ids[0]}`);
    }
  } else {
    posTotal += 1;
    const rank = ids.indexOf(expect) + 1;
    if (rank > 0) {
      posHit += 1;
      mrrSum += 1 / rank;
      out(`${q} ${"HIT".padEnd(8)} rank ${rank}`);
    } else {
      out(
        `${q} ${"MISS".padEnd(8)} expected ${expect.slice(0, 12)}… not in top${K}`,
      );
    }
  }
}

const recallPct = posTotal ? Math.floor((100 * posHit) / posTotal) : 100;
const abstainPct = absTotal ? Math.floor((100 * absOk) / absTotal) : 100;
const mrr = posTotal ? mrrSum / posTotal : 0;
out("---");
out(
  `Recall@${K} = ${posHit}/${posTotal} (${recallPct}%) · MRR = ${mrr.toFixed(3)} · Abstention (cross-domain) = ${absOk}/${absTotal} (${abstainPct}%)`,
);

let fail = 0;
if (recallPct < RECALL_THRESHOLD) {
  out(`FAIL: Recall@${K} below ${RECALL_THRESHOLD}%`);
  fail = 1;
}
if (abstainPct < ABSTAIN_THRESHOLD) {
  out(`FAIL: abstention below ${ABSTAIN_THRESHOLD}%`);
  fail = 1;
}
if (fail === 0) out("PASS: recall quality thresholds met");
process.exit(fail);
