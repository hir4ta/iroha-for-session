#!/usr/bin/env bash
# rerank-setup.sh — OPT-IN setup for the HEAVY (hybrid) recall tier: a dense bi-encoder candidate
# generator + a cross-encoder reranker. iroha's proactive recall works out of the box on the
# pure-bash BM25 stage (no deps, no model). This adds the higher-quality tier:
#   - DENSE retrieval (embed.mjs): surfaces the semantic near-matches BM25 misses (zero lexical
#     overlap), recovering candidate-GENERATION misses the reranker alone cannot.
#   - RERANK (rerank.mjs): PROMOTES the strong matches above the BM25 advisory list.
# It is opt-in because it is HEAVY — a Node runtime dep (@huggingface/transformers) + two local
# models (hundreds of MB each). A fresh install that never runs this pays nothing and keeps the
# pure-bash BM25 behavior.
#
# Run once: bash scripts/rerank-setup.sh
# Override either model before running (e.g. a lighter, Japanese-specialized reranker):
#   IROHA_RERANK_MODEL=hotchpotch/japanese-reranker-xsmall-v2 IROHA_RERANK_DTYPE=fp32 bash scripts/rerank-setup.sh
set -u

PR="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="${IROHA_RERANK_MODEL:-onnx-community/bge-reranker-v2-m3-ONNX}"
DTYPE="${IROHA_RERANK_DTYPE:-q8}"
EMODEL="${IROHA_EMBED_MODEL:-Xenova/multilingual-e5-small}"
EDTYPE="${IROHA_EMBED_DTYPE:-q8}"
MODELDIR="${IROHA_MODEL_DIR:-$HOME/.iroha/models}"

command -v node >/dev/null 2>&1 || { echo "rerank-setup: node is required (>=18)"; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "rerank-setup: npm is required"; exit 1; }

echo "1/4  Installing the Node runtime (@huggingface/transformers) into the plugin…"
# --no-save keeps the SHIPPED package.json lean (a default install stays dependency-free); this is a
# per-user opt-in. Re-run this script after a clean reinstall to restore it.
( cd "$PR" && npm install --no-save @huggingface/transformers ) || {
  echo "rerank-setup: npm install failed"; exit 1; }

echo "2/4  Downloading the reranker model ($MODEL, dtype=$DTYPE) to $MODELDIR …"
echo "     (one-time; the default bge-reranker-v2-m3 is ~570MB — Ctrl-C and set a lighter"
echo "      IROHA_RERANK_MODEL=hotchpotch/japanese-reranker-xsmall-v2 if you prefer ~37MB.)"
mkdir -p "$MODELDIR"
warm=$(printf '{"query":"warmup","docs":[{"id":"w","text":"warmup passage"}],"threshold":0.0,"topn":1}' \
  | IROHA_RERANK_ALLOW_DOWNLOAD=1 IROHA_MODEL_DIR="$MODELDIR" IROHA_RERANK_MODEL="$MODEL" \
    IROHA_RERANK_DTYPE="$DTYPE" node "$PR/scripts/rerank.mjs" 2>&1)
rc=$?
if [ "$rc" != 0 ]; then
  echo "rerank-setup: reranker download/load failed (exit $rc):"
  printf '%s\n' "$warm" | tail -5
  exit 1
fi

echo "3/4  Downloading the dense embedder ($EMODEL, dtype=$EDTYPE) to $MODELDIR …"
echo "     (one-time; multilingual-e5-small is ~120MB — the dense lane that recovers the semantic"
echo "      near-matches BM25 misses.)"
ewarm=$(printf '{"query":"warmup","docs":[{"id":"w","text":"warmup passage"}],"topk":1}' \
  | IROHA_EMBED_ALLOW_DOWNLOAD=1 IROHA_MODEL_DIR="$MODELDIR" IROHA_EMBED_MODEL="$EMODEL" \
    IROHA_EMBED_DTYPE="$EDTYPE" node "$PR/scripts/embed.mjs" 2>&1)
rc=$?
if [ "$rc" != 0 ]; then
  echo "rerank-setup: embedder download/load failed (exit $rc):"
  printf '%s\n' "$ewarm" | tail -5
  exit 1
fi

echo "4/4  Arming the heavy recall tier (rerank_enabled=true) …"
bun "$PR/scripts/_lib/config.ts" set rerank_enabled true

cat <<EOF

Done. Proactive recall now runs the hybrid tier: BM25 ∪ dense candidates -> the cross-encoder
promotes the strong matches above the BM25 advisory list (higher recall AND precision, locally).
  reranker:  $MODEL ($DTYPE)
  embedder:  $EMODEL ($EDTYPE)
  model dir: $MODELDIR
  disable:   IROHA_RERANK_DISABLE=1  (per session)  /  config.ts set rerank_enabled false  (persistent)
  verify:    IROHA_MODEL_DIR=$MODELDIR bash tests/hybrid-eval.sh   (recall+abstention end-to-end)
             IROHA_MODEL_DIR=$MODELDIR bash tests/rerank-eval.sh   (cross-encoder unit precision)
EOF
