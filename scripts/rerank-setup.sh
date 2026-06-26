#!/usr/bin/env bash
# rerank-setup.sh — OPT-IN setup for the cross-encoder rerank precision stage.
#
# iroha's proactive recall works out of the box on the pure-bash BM25 stage (no deps, no model).
# This adds the higher-PRECISION second stage: a local cross-encoder reranker that filters out the
# same-vocabulary-but-off-topic decisions BM25 cannot separate (measured: it drives false
# injections to zero while keeping the real matches). It is opt-in because it is HEAVY — it adds a
# Node runtime dep (@huggingface/transformers) and downloads a local model (hundreds of MB). A fresh
# install that never runs this pays nothing and keeps the BM25 behavior.
#
# Run once: bash scripts/rerank-setup.sh
# Override the model (e.g. the lighter, Japanese-specialized option) before running:
#   IROHA_RERANK_MODEL=hotchpotch/japanese-reranker-xsmall-v2 IROHA_RERANK_DTYPE=fp32 bash scripts/rerank-setup.sh
set -u

PR="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="${IROHA_RERANK_MODEL:-onnx-community/bge-reranker-v2-m3-ONNX}"
DTYPE="${IROHA_RERANK_DTYPE:-q8}"
MODELDIR="${IROHA_MODEL_DIR:-$HOME/.iroha-for-notion/models}"

command -v node >/dev/null 2>&1 || { echo "rerank-setup: node is required (>=18)"; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "rerank-setup: npm is required"; exit 1; }

echo "1/3  Installing the Node reranker runtime (@huggingface/transformers) into the plugin…"
# --no-save keeps the SHIPPED package.json lean (a default install stays dependency-free); this is a
# per-user opt-in. Re-run this script after a clean reinstall to restore it.
( cd "$PR" && npm install --no-save @huggingface/transformers ) || {
  echo "rerank-setup: npm install failed"; exit 1; }

echo "2/3  Downloading the reranker model ($MODEL, dtype=$DTYPE) to $MODELDIR …"
echo "     (one-time; the default bge-reranker-v2-m3 is ~570MB — Ctrl-C and set a lighter"
echo "      IROHA_RERANK_MODEL=hotchpotch/japanese-reranker-xsmall-v2 if you prefer ~37MB.)"
mkdir -p "$MODELDIR"
warm=$(printf '{"query":"warmup","docs":[{"id":"w","text":"warmup passage"}],"threshold":0.0,"topn":1}' \
  | IROHA_RERANK_ALLOW_DOWNLOAD=1 IROHA_MODEL_DIR="$MODELDIR" IROHA_RERANK_MODEL="$MODEL" \
    IROHA_RERANK_DTYPE="$DTYPE" node "$PR/scripts/rerank.mjs" 2>&1)
rc=$?
if [ "$rc" != 0 ]; then
  echo "rerank-setup: model download/load failed (exit $rc):"
  printf '%s\n' "$warm" | tail -5
  exit 1
fi

echo "3/3  Arming the rerank gate (rerank_enabled=true) …"
bash "$PR/scripts/_lib/config.sh" set rerank_enabled true

cat <<EOF

Done. Proactive recall now reranks BM25 candidates with the local cross-encoder for higher precision.
  model:     $MODEL ($DTYPE)
  model dir: $MODELDIR
  disable:   IROHA_RERANK_DISABLE=1  (per session)  /  config.sh set rerank_enabled false  (persistent)
  verify:    IROHA_MODEL_DIR=$MODELDIR bash tests/rerank-eval.sh
EOF
