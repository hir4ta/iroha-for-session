#!/usr/bin/env bash
# recall.sh — the shared LOCAL recall orchestration: BM25 (always) ∪ dense (opt-in), reranker as a
# PROMOTER (opt-in). One code path, used by BOTH the UserPromptSubmit hook (hooks/recall-inject.sh)
# AND the quality oracle (tests/hybrid-eval.sh), so the eval measures exactly what production does.
#
#   FREE tier  (default, no deps):   pure-jq BM25 over the keys-only index (scripts/_lib/search.sh).
#   HEAVY tier (opt-in, armed):      BM25 hits ∪ DENSE candidates (scripts/embed.mjs); the
#                                    cross-encoder reranker (scripts/rerank.mjs) PROMOTES the strong
#                                    (dense-discovered) matches above the BM25 advisory list.
#
# Why the reranker promotes but never vetoes. Measured on this corpus the cross-encoder is bimodal:
# a near-paraphrase scores >0.4, but a terse, real, lexically-strong match (e.g. "連結: relation
# でなく URL" for "…連結にrelationを使うべきか") scores ~0.003 — indistinguishable from an off-topic
# pair. So using the reranker as a VETO drops genuine BM25 hits (a measured recall regression that
# the old BM25-only recall-eval never saw, because the user's armed rerank tier was never evaluated
# end-to-end). The fix: BM25 lexical hits are sacrosanct (recall is the north star); the reranker
# only LIFTS high-confidence semantic matches the dense lane surfaced (recovering candidate-
# GENERATION misses BM25 cannot) above them. Result: hybrid recall >= BM25 recall, monotonically.
#
# Abstention is preserved: a true cross-domain prompt yields no BM25 lexical hit AND no dense
# candidate clears the reranker's "strong" threshold -> empty -> honest silence.
#
# Output: one compact JSON object per line, best first: {score,type,id,topic,status,date,title}.
set -u

iroha_recall_local() { # <root> <query> [topn] -> JSON lines, ranked
  local root="$1" query="$2" topn="${3:-3}"
  local pr idx L
  pr="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  idx="$root/.iroha/index.ndjson"
  L="$pr/scripts/_lib/config.sh"
  [ -f "$idx" ] || return 0

  # Heavy tier on only when node is present AND (armed in config OR forced for eval).
  local heavy=0
  if [ "${IROHA_RERANK_DISABLE:-}" != "1" ] && command -v node >/dev/null 2>&1 \
     && { [ "$(bash "$L" get rerank_enabled 2>/dev/null)" = "true" ] \
          || [ "${IROHA_RECALL_FORCE_HEAVY:-}" = "1" ]; }; then
    heavy=1
  fi

  # 1. BM25 candidates. A wide net when the heavy tier will fuse/rerank; exactly topn otherwise.
  local cand_n bm_hits
  cand_n="$topn"
  [ "$heavy" = 1 ] && cand_n="${IROHA_RERANK_CANDIDATES:-8}"
  bm_hits=$(bash "$pr/scripts/_lib/search.sh" "$root" "$query" "" \
    "$cand_n" "${IROHA_RECALL_MINSCORE:-1.2}" 2>/dev/null)

  if [ "$heavy" != 1 ]; then
    printf '%s\n' "$bm_hits" | sed '/^$/d'   # FREE tier: pure BM25 advisory
    return 0
  fi

  local bm_ids
  bm_ids=$(printf '%s\n' "$bm_hits" | jq -r 'select(.id)|.id' 2>/dev/null)

  # 2. Dense candidates (opt-in). embed.mjs ranks the WHOLE index by cosine, surfacing semantic
  #    near-matches BM25 missed. exit 3 (no model) -> empty -> proceed with BM25 candidates only.
  local docs dense dense_ids
  docs=$(jq -s -c '[ .[] | {id, text: ([.title,.topic,.text]|map(select(.!=null and .!=""))|join(" "))} ]' "$idx" 2>/dev/null)
  dense=""
  if [ -n "$docs" ] && [ "$docs" != "[]" ]; then
    dense=$(jq -nc --arg q "$query" --argjson docs "$docs" --argjson k "${IROHA_DENSE_CANDIDATES:-8}" \
      '{query:$q, docs:$docs, topk:$k}' \
      | IROHA_MODEL_DIR="${IROHA_MODEL_DIR:-$HOME/.iroha/models}" \
        node "$pr/scripts/embed.mjs" 2>/dev/null) || dense=""
  fi
  dense_ids=$(printf '%s' "$dense" | jq -r '.[]?.id // empty' 2>/dev/null)

  # 3. Candidate union (for the reranker to judge): BM25 ids first, then any new dense id.
  local union_ids
  union_ids=$(printf '%s\n%s\n' "$bm_ids" "$dense_ids" | awk 'NF && !seen[$0]++')
  [ -z "$union_ids" ] && return 0

  # 4. Reranker as PROMOTER. Score the union; keep only the "strong" (>= threshold) survivors — these
  #    are the high-confidence (typically dense-discovered) semantic matches that should outrank the
  #    BM25 advisory list. A BM25 hit that the reranker rates low is NOT dropped (step 5).
  local ids_json cand_docs payload survivors rc strong_ids
  ids_json=$(printf '%s\n' "$union_ids" | jq -R . | jq -s -c .)
  cand_docs=$(jq -s -c --argjson ids "$ids_json" '
    [ .[] | select(.id as $i | $ids | index($i)) | {id, text: ([.title,.topic,.text]|map(select(.!=null and .!=""))|join(" "))} ]' "$idx" 2>/dev/null)
  payload=$(jq -nc --arg q "$query" --argjson docs "$cand_docs" \
    --argjson th "${IROHA_RERANK_THRESHOLD:-0.05}" --argjson tn 50 \
    '{query:$q, docs:$docs, threshold:$th, topn:$tn}' 2>/dev/null)
  survivors=$(printf '%s' "$payload" \
    | IROHA_MODEL_DIR="${IROHA_MODEL_DIR:-$HOME/.iroha/models}" \
      node "$pr/scripts/rerank.mjs" 2>/dev/null)
  rc=$?
  strong_ids=""
  [ "$rc" = 0 ] && [ -n "$survivors" ] && strong_ids=$(printf '%s' "$survivors" | jq -r '.[].id' 2>/dev/null)

  # 5. Final ranking: strong semantic matches (rerank order) first, then the remaining BM25 hits
  #    (BM25 order). BM25 hits are never dropped -> recall is monotonic vs the free tier. Abstain
  #    only when BOTH are empty (no lexical hit and nothing cleared the strong bar).
  local final_ids
  final_ids=$(printf '%s\n%s\n' "$strong_ids" "$bm_ids" | awk 'NF && !seen[$0]++' | head -n "$topn")
  [ -z "$final_ids" ] && return 0

  # Emit full records in final order; carry the rerank score when strong, else the BM25 score.
  local bm_json
  bm_json=$(printf '%s\n' "$bm_hits" | jq -s -c '.' 2>/dev/null)
  printf '%s\n' "$final_ids" | jq -R . | jq -s -c \
    --slurpfile all "$idx" --argjson surv "${survivors:-[]}" --argjson bm "${bm_json:-[]}" '
    ($all | map({key:.id, value:.}) | from_entries) as $m
    | (($bm | map({key:.id, value:.score}) | from_entries)
       + ($surv | map({key:.id, value:.score}) | from_entries)) as $sc
    | .[] | $m[.] as $r | select($r != null)
    | {score: ($sc[.] // 0), type:$r.type, id:$r.id, topic:$r.topic,
       status:$r.status, date:$r.date, title:$r.title}' 2>/dev/null
}

# CLI: `bash recall.sh <root> <query> [topn]`. Guarded so sourcing is a no-op.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  command -v jq >/dev/null 2>&1 || { echo "recall.sh: jq is required" >&2; exit 1; }
  iroha_recall_local "${1:-}" "${2:-}" "${3:-3}"
fi
