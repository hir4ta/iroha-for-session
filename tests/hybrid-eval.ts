// hybrid-eval.ts — quality oracle for the HEAVY recall tier (BM25 ∪ dense -> cross-encoder rerank).
//
// recall-eval measures the FREE tier (BM25). This measures the opt-in HEAVY tier on the SAME golden
// set (tests/golden-recall.txt), through the exact production code path (scripts/_lib/recall.ts ::
// recallLocal), so the eval reflects what a user with the models installed actually gets. It reports
// Recall@k, MRR and abstention, and runs the FREE tier (pure BM25) for the SAME queries so it can
// prove the heavy tier's actual guarantee — MONOTONICITY: the dense lane only ADDS candidates, BM25
// hits are sacrosanct, so the heavy path must never drop a BM25 hit (the recall regression the old
// VETO tier silently caused; this eval is its guard). Which golden queries are "BM25 misses the
// dense lane recovers" is DERIVED from comparing the two tiers per query. Recovery is REPORTED, not
// gated: on a terse-Japanese corpus the cross-encoder scores real-but-terse matches ~0, so 0
// recovery is the documented, expected reality, not a regression.
//
// It SKIPs (exit 0) when the opt-in models are not installed, exactly like rerank-eval. Run the real
// thing with the models present: IROHA_MODEL_DIR=$HOME/.iroha/models bun tests/hybrid-eval.ts

import { mkdtempSync, readFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { recallLocal } from "../scripts/_lib/recall.ts";
import { search } from "../scripts/_lib/search.ts";
import { denseRank } from "../scripts/embed.ts";
import { rerankPromote } from "../scripts/rerank.ts";

const out = (s: string) => process.stdout.write(`${s}\n`);

const ROOT = process.env.IROHA_EVAL_ROOT ?? join(import.meta.dir, "..");
const GOLDEN_FILE = join(import.meta.dir, "golden-recall.txt");
const K = 3;
const MINSCORE = Number(process.env.IROHA_RECALL_MINSCORE ?? "1.2");
const MODEL_DIR =
  process.env.IROHA_MODEL_DIR ?? join(homedir(), ".iroha", "models");

// Exercise the heavy path without mutating the user's config: force heavy + isolate the config dir
// (FORCE_HEAVY makes the rerank_enabled value irrelevant, so an empty config is fine).
process.env.IROHA_MODEL_DIR = MODEL_DIR;
process.env.IROHA_RECALL_FORCE_HEAVY = "1";
process.env.IROHA_CONFIG_DIR = mkdtempSync(join(tmpdir(), "iroha-hybrid-cfg-"));

// Probe both opt-in models in-process (no download); SKIP cleanly if either is absent. denseRank /
// rerankPromote throw when the dep/model is missing — the exact gate the production path falls back
// on. Runs under Bun, no node subprocess.
try {
  await denseRank("w", [{ id: "w", text: "w" }], 1);
  await rerankPromote("w", [{ id: "w", text: "w" }], 0, 1);
} catch (e) {
  out(
    `hybrid-eval: SKIP (opt-in models not installed: ${e instanceof Error ? e.message : e})`,
  );
  out(
    "  install with: bun scripts/rerank-setup.ts   (downloads both the reranker and embedder)",
  );
  process.exit(0);
}

const golden = readFileSync(GOLDEN_FILE, "utf8")
  .split("\n")
  .map((l) => l.trim())
  .filter((l) => l !== "" && !l.startsWith("#"));

let posTotal = 0;
let posHit = 0;
let mrrSum = 0;
let absTotal = 0;
let absOk = 0;
let bmHit = 0;
let recovered = 0;
let regressed = 0;

out(
  `=== hybrid-eval (Recall@${K}, heavy tier: BM25 ∪ dense -> rerank) over ${ROOT}/.iroha/index.ndjson ===`,
);
out(`${"query".padEnd(52)} ${"result".padEnd(8)} rank/expected`);

for (const line of golden) {
  const [query, expect] = line.split("|");
  if (!query || expect === undefined) continue;
  // HEAVY = the production heavy path (FORCE_HEAVY). FREE = pure BM25, the EXACT free-tier call.
  const heavyIds = (await recallLocal(ROOT, query, K)).map((h) => h.id);
  const freeIds = search(ROOT, query, "", K, MINSCORE).map((h) => h.id);
  const q = query.slice(0, 50).padEnd(52);
  if (expect === "NONE") {
    absTotal += 1;
    if (heavyIds.length === 0) {
      absOk += 1;
      out(`${q} ${"ABSTAIN".padEnd(8)} ok (no hit)`);
    } else {
      out(`${q} ${"LEAK".padEnd(8)} got ${heavyIds[0]}`);
    }
  } else {
    posTotal += 1;
    const hrank = heavyIds.indexOf(expect) + 1;
    const frank = freeIds.indexOf(expect) + 1;
    if (frank > 0) bmHit += 1;
    if (hrank > 0) {
      posHit += 1;
      mrrSum += 1 / hrank;
      if (frank === 0) {
        recovered += 1; // BM25 missed it; dense+rerank promoted it back
        out(`${q} ${"RECOVER".padEnd(8)} rank ${hrank}`);
      } else {
        out(`${q} ${"HIT".padEnd(8)} rank ${hrank}`);
      }
    } else {
      // A heavy MISS of something BM25 HIT is a MONOTONICITY REGRESSION.
      if (frank > 0) regressed += 1;
      const note =
        frank > 0
          ? `REGRESSION: BM25 had it at rank ${frank}, heavy dropped it`
          : `expected ${expect.slice(0, 12)}… not in top${K}`;
      out(`${q} ${"MISS".padEnd(8)} ${note}`);
    }
  }
}

// SAME-VOCABULARY soft negatives (REPORTED, not gated). These share the corpus's software vocabulary
// but ask about something iroha has NO decision on, so the only "match" is a wrong nearest neighbour.
// iroha's stance is recall-first: hook hits are advisory, so a same-vocab leak is low-harm noise; the
// floor is intentionally NOT raised to suppress it at recall's expense. We REPORT the soft-leak rate
// but do not fail on it. Cross-domain abstention above IS gated — a true off-domain leak is a bug.
const softNeg = [
  "Notionに画像をアップロードする方法を教えて",
  "bashスクリプトのテストをどう書くか",
  "jqでJSONをパースする方法",
  "gitのブランチ戦略を決めたい",
];
let softTotal = 0;
let softQuiet = 0;
for (const q of softNeg) {
  softTotal += 1;
  if ((await recallLocal(ROOT, q, K)).length === 0) softQuiet += 1;
}

const recallPct = posTotal ? Math.floor((100 * posHit) / posTotal) : 100;
const bmPct = posTotal ? Math.floor((100 * bmHit) / posTotal) : 100;
const abstainPct = absTotal ? Math.floor((100 * absOk) / absTotal) : 100;
const mrr = posTotal ? mrrSum / posTotal : 0;
out("---");
out(
  `same-vocab soft negatives quiet: ${softQuiet}/${softTotal} (reported only — recall-first, low-harm advisory)`,
);
out(
  `Recall@${K} = ${posHit}/${posTotal} (${recallPct}%) · BM25 baseline = ${bmHit}/${posTotal} (${bmPct}%) · recovered = ${recovered} · regressed = ${regressed} · MRR = ${mrr.toFixed(3)} · Abstention = ${absOk}/${absTotal} (${abstainPct}%)`,
);

// Gates. The heavy tier's GUARANTEE is MONOTONICITY: hybrid recall >= BM25 recall. `regressed` counts
// exactly that violation per query (stronger than comparing aggregate percentages). RECOVERY is a
// corpus-dependent BONUS, REPORTED not gated.
const RECALL_THRESHOLD = 86;
let fail = 0;
if (abstainPct < 100) {
  out("FAIL: abstention below 100% (a false hit is the worst failure)");
  fail = 1;
}
if (recallPct < RECALL_THRESHOLD) {
  out(`FAIL: Recall@${K} below baseline ${RECALL_THRESHOLD}%`);
  fail = 1;
}
if (regressed > 0) {
  out(
    `FAIL: heavy tier dropped ${regressed} BM25 hit(s) — monotonicity violated (hybrid recall < BM25 recall)`,
  );
  fail = 1;
}
if (fail === 0)
  out(
    `PASS: hybrid recall >= BM25 (no regression), abstention 100%; recovered ${recovered} BM25 miss(es) on this corpus`,
  );
process.exit(fail);
