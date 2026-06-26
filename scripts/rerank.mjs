#!/usr/bin/env node
// rerank.mjs — local, offline cross-encoder reranker: the PRECISION gate for proactive recall.
//
// Why this exists. The cheap always-on first stage (scripts/_lib/search.sh, pure-jq BM25) has
// great recall but limited precision on a small single-domain corpus: a prompt that merely shares
// the project's vocabulary ("upload an image to Notion", "how to write bash tests") lexically
// matches an unrelated decision and, measured, can outscore a genuinely relevant one — so a higher
// floor cannot separate them. A cross-encoder reranker CAN: it scores the (query, decision) PAIR
// for actual relevance, crushing same-vocabulary-but-off-topic candidates to ~0 while keeping real
// matches high (measured: 0/7 false injections on hard negatives, real matches rank #1).
//
// This is the verified-but-INVARIANT-BREAKING half: it adds a Node runtime + the
// @huggingface/transformers dep + a ~570MB local model. It is therefore strictly OPT-IN — a fresh
// install pays nothing and keeps the pure-bash BM25 advisory behavior; only a user who runs the
// rerank setup and arms it (config rerank_enabled=true) pays the cost. It supersedes the earlier
// decision "リコール精度: lexical据置". Still NO API token and NO network at query time (the model
// is local and cached); the broken invariant is "pure bash / zero deps", not "no token / offline".
//
// Contract (so the bash hook stays simple and this stays file-agnostic):
//   stdin  = JSON {"query": "...", "docs": [{"id": "...", "text": "..."}], "threshold": 0.05, "topn": 3}
//   stdout = JSON array of survivors [{"id": "...", "score": 0.83}], score >= threshold, desc, <= topn
//   exit 0   = reranked OK (array may be empty = confident abstain: nothing is relevant)
//   exit 3   = runtime/model unavailable -> the CALLER must fall back to the BM25 advisory result
//   exit 2   = bad input
// The exit-3 / exit-0-empty distinction matters: exit 3 means "could not judge" (keep BM25 hits),
// empty-array-exit-0 means "judged everything irrelevant" (inject nothing — the precision win).

let raw = "";
for await (const chunk of process.stdin) raw += chunk;

let input;
try {
  input = JSON.parse(raw);
} catch {
  process.stderr.write("rerank: invalid JSON on stdin\n");
  process.exit(2);
}
const query = input.query;
const docs = Array.isArray(input.docs) ? input.docs : [];
const threshold = typeof input.threshold === "number" ? input.threshold : 0.05;
const topn = typeof input.topn === "number" ? input.topn : 3;
if (!query || docs.length === 0) {
  // Nothing to rerank — emit an empty result rather than erroring (caller treats as abstain).
  process.stdout.write("[]\n");
  process.exit(0);
}

// Model is per-user and cached (survives plugin reinstall), like config.json. Default to the
// Transformers.js-compatible ONNX export of bge-reranker-v2-m3 (strong multilingual incl Japanese).
const MODEL =
  process.env.IROHA_RERANK_MODEL || "onnx-community/bge-reranker-v2-m3-ONNX";
const DTYPE = process.env.IROHA_RERANK_DTYPE || "q8";

let AutoModelForSequenceClassification, AutoTokenizer, env;
try {
  ({ AutoModelForSequenceClassification, AutoTokenizer, env } = await import(
    "@huggingface/transformers"
  ));
} catch {
  // Dependency not installed -> the user has not opted in. Signal fallback, do not crash the hook.
  process.stderr.write(
    "rerank: @huggingface/transformers not installed (run the rerank setup to opt in)\n",
  );
  process.exit(3);
}

// Keep the model under the per-user iroha dir so it is found regardless of cwd / plugin reinstall.
if (process.env.IROHA_MODEL_DIR) env.cacheDir = process.env.IROHA_MODEL_DIR;
// Hook safety: NEVER download at query time (a first-prompt 570MB fetch would blow the hook's ~5s
// budget and hang the prompt). The setup step pre-downloads with IROHA_RERANK_ALLOW_DOWNLOAD=1; at
// hook time we use the cached model only, and a cache miss cleanly falls back to BM25 (exit 3).
if (process.env.IROHA_RERANK_ALLOW_DOWNLOAD !== "1")
  env.allowRemoteModels = false;
// Be quiet on stdout (it carries the result); transformers logs to stderr already.

let tokenizer, model;
try {
  tokenizer = await AutoTokenizer.from_pretrained(MODEL);
  model = await AutoModelForSequenceClassification.from_pretrained(MODEL, {
    dtype: DTYPE,
  });
} catch (e) {
  // Model not downloaded yet (offline first run) or load failed -> fall back to BM25.
  process.stderr.write(
    `rerank: model load failed (${e?.message || e}); falling back\n`,
  );
  process.exit(3);
}

async function relevance(q, d) {
  const inputs = tokenizer(q, {
    text_pair: d,
    padding: true,
    truncation: true,
  });
  const { logits } = await model(inputs);
  return 1 / (1 + Math.exp(-logits.data[0])); // sigmoid(logit) -> 0..1 relevance
}

const scored = [];
for (const doc of docs) {
  if (!doc?.id || !doc?.text) continue;
  try {
    scored.push({ id: doc.id, score: await relevance(query, doc.text) });
  } catch {
    // Skip a single bad pair rather than failing the whole rerank.
  }
}

const survivors = scored
  .filter((s) => s.score >= threshold)
  .sort((a, b) => b.score - a.score)
  .slice(0, topn)
  .map((s) => ({ id: s.id, score: Math.round(s.score * 1000) / 1000 }));

process.stdout.write(`${JSON.stringify(survivors)}\n`);
process.exit(0);
