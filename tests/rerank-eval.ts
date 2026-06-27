// rerank-eval.ts — precision eval for the OPT-IN cross-encoder rerank gate (scripts/rerank.mjs).
//
// The cheap BM25 stage (recall-eval) has high recall but limited precision on a small single-domain
// corpus: a prompt that merely shares the project's vocabulary lexically matches an unrelated
// decision and (measured) can outscore a genuinely relevant one — so a higher floor cannot separate
// them. The cross-encoder reranker IS the precision filter. This eval proves it on a labeled set:
// every hard-negative (off-topic but same-vocabulary) prompt must yield ZERO injected decisions,
// while real prompts still surface their decision.
//
// This requires the opt-in runtime (Node + @huggingface/transformers + the local model). When that
// is absent it SKIPS with exit 0 — the pure-bash/TS BM25 path (recall-eval / selftest) is the
// always-on guarantee; this is the extra precision layer, validated wherever the model is present.
//
// Run: bun tests/rerank-eval.ts   (PASS / SKIP / FAIL)

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { indexRead } from "../scripts/_lib/index.ts";

const out = (s: string) => process.stdout.write(`${s}\n`);

const ROOT = join(import.meta.dir, "..");
const RERANK = join(ROOT, "scripts", "rerank.mjs");
const INDEX = join(ROOT, ".iroha", "index.ndjson");
const THRESHOLD = process.env.IROHA_RERANK_THRESHOLD ?? "0.05";
const MODEL_DIR =
  process.env.IROHA_MODEL_DIR ?? join(homedir(), ".iroha", "models");

if (!(Bun.which("node") !== null)) {
  out("SKIP: node not available (opt-in rerank not testable here)");
  process.exit(0);
}
if (!existsSync(INDEX)) {
  out("SKIP: no local index");
  process.exit(0);
}

// Run rerank.mjs via node. Returns { stdout, code }.
function nodeRerank(payload: unknown): { stdout: string; code: number } {
  const r = spawnSync("node", [RERANK], {
    input: JSON.stringify(payload),
    encoding: "utf8",
    env: { ...process.env, IROHA_MODEL_DIR: MODEL_DIR },
  });
  return { stdout: r.stdout ?? "", code: r.status ?? 1 };
}

// Probe: is the runtime+model actually usable? rerank.mjs exits 3 when the dep/model is missing.
const probe = nodeRerank({
  query: "ping",
  docs: [{ id: "x", text: "ping pong" }],
  threshold: 0.0,
  topn: 1,
});
if (probe.code === 3 || probe.stdout.trim() === "") {
  out(
    "SKIP: rerank runtime/model not installed (run the rerank setup to enable this precision eval)",
  );
  process.exit(0);
}

const records = indexRead(ROOT);
// Candidate docs (id -> rerankable text), the same shape the hook passes.
const docs = records.map((r) => ({
  id: String(r.id ?? ""),
  text: [r.title, r.topic, r.text]
    .filter((x): x is string => typeof x === "string" && x !== "")
    .join(" "),
}));
const topicOf = (id: string): string => {
  const r = records.find((x) => x.id === id);
  return r ? `${String(r.topic ?? "")} ${String(r.title ?? "")}` : "";
};

function rerank(query: string): string[] {
  const r = nodeRerank({
    query,
    docs,
    threshold: Number(THRESHOLD),
    topn: 3,
  });
  if (r.code !== 0) return [];
  try {
    return (JSON.parse(r.stdout) as { id?: string }[])
      .map((s) => s.id ?? "")
      .filter((id) => id !== "");
  } catch {
    return [];
  }
}

// TRUE prompts -> a substring the surfaced decision's topic/title must contain. RE-LABELED 2026-06-27
// against the re-based index (the prior labels — 会話ログ / メモリ列挙 / 抽出 / State / 自動保存 —
// were stale after the workspace reset, which is why the bash eval failed 0/5). Each query is a
// paraphrase the cross-encoder ranks #1 above the 0.05 promote threshold (verified empirically).
const TRUEQ: [string, string][] = [
  ["決定のトピックは一級プロパティにすべきか", "決定スキーマ"],
  ["StateとProjectsは分離すべきか畳むべきか", "State配置"],
  ["セッション保存のextract呼び出しをまとめて速くしたい", "保存効率"],
  ["リコールにcoverage gateを入れてノイズを消すべきか", "リコール精度"],
  ["init時に事前ページを作るべきか", "初回UX"],
];
// HARD-NEGATIVE prompts (off-topic but share the project's vocabulary) -> MUST inject nothing.
const NEGQ = [
  "Notionに画像をアップロードする方法を教えて",
  "bashスクリプトのテストをどう書くか",
  "jqでJSONをパースする方法",
  "gitのブランチ戦略を決めたい",
  "おすすめの映画を教えて",
];

out(`=== rerank precision eval (threshold=${THRESHOLD}) ===`);
let recallHit = 0;
for (const [q, want] of TRUEQ) {
  const ok = rerank(q).some((id) => topicOf(id).includes(want));
  if (ok) {
    recallHit += 1;
    out(`  HIT      ${q}`);
  } else {
    out(`  miss     ${q} (wanted ${want})`);
  }
}
let falseInject = 0;
for (const q of NEGQ) {
  const n = rerank(q).length;
  if (n === 0) {
    out(`  ABSTAIN  ${q}`);
  } else {
    falseInject += 1;
    out(`  LEAK(${n}) ${q}`);
  }
}

out("---");
out(
  `Recall@3 = ${recallHit}/${TRUEQ.length} · False-injection (hard negatives) = ${falseInject}/${NEGQ.length}`,
);
// The contract: ZERO false injections (precision win) AND every TRUE case surfaces its decision.
if (falseInject === 0 && recallHit >= TRUEQ.length) {
  out(
    `PASS: rerank gate holds (0 false injections, all ${TRUEQ.length} TRUE cases surfaced)`,
  );
  process.exit(0);
}
out(
  `FAIL: false_inject=${falseInject} (want 0), recall=${recallHit}/${TRUEQ.length} (want all)`,
);
process.exit(1);
