#!/usr/bin/env bash
# hybrid-eval.sh — quality oracle for the HEAVY recall tier (BM25 ∪ dense -> cross-encoder rerank).
#
# recall-eval.sh measures the FREE tier (pure-jq BM25). This measures the opt-in HEAVY tier on the
# SAME golden set (tests/golden-recall.txt), through the exact production code path
# (scripts/_lib/recall.sh :: iroha_recall_local), so the eval reflects what a user with the models
# installed actually gets. It reports Recall@k, MRR and abstention, and — because the heavy tier
# exists to close candidate-GENERATION misses BM25 cannot — it specifically tracks the cases that
# the BM25 tier MISSES, proving which the dense lane recovers.
#
# It SKIPs (exit 0, no failure) when the opt-in models are not installed, exactly like
# rerank-eval.sh, so a fresh CI checkout without the ~hundreds-of-MB models is green. Run the real
# thing with the models present:  IROHA_MODEL_DIR=$HOME/.iroha/models bash tests/hybrid-eval.sh
set -u

ROOT="${IROHA_EVAL_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PR="$(cd "$(dirname "$0")/.." && pwd)"
GOLDEN_FILE="$(dirname "$0")/golden-recall.txt"
K=3
# These two queries are the BM25-tier MISSes (candidate-generation misses): the decision shares
# little surface vocabulary with the prompt, so a wider floor / the reranker alone cannot recover it.
# The dense lane is the reason they can re-enter the candidate pool — track them explicitly.
BM25_MISSES="リコールの設計方針はどうする
セッション終了時に自動でNotionへ保存すべきか"

export IROHA_MODEL_DIR="${IROHA_MODEL_DIR:-$HOME/.iroha/models}"
export IROHA_RECALL_FORCE_HEAVY=1   # exercise the heavy path without mutating the user's config

command -v node >/dev/null 2>&1 || { echo "hybrid-eval: SKIP (node not installed — opt-in tier)"; exit 0; }

# Probe both opt-in models with a no-download warmup; SKIP cleanly if either is absent.
printf '{"query":"w","docs":[{"id":"w","text":"w"}],"topk":1}' \
  | node "$PR/scripts/embed.mjs" >/dev/null 2>&1; rc_e=$?
printf '{"query":"w","docs":[{"id":"w","text":"w"}],"threshold":0,"topn":1}' \
  | node "$PR/scripts/rerank.mjs" >/dev/null 2>&1; rc_r=$?
if [ "$rc_e" != 0 ] || [ "$rc_r" != 0 ]; then
  echo "hybrid-eval: SKIP (opt-in models not installed: embed rc=$rc_e, rerank rc=$rc_r)"
  echo "  install with: bash scripts/rerank-setup.sh   (downloads both the reranker and embedder)"
  exit 0
fi

# shellcheck disable=SC1091 # dynamic source path; the file exists at runtime
. "$PR/scripts/_lib/recall.sh"

pos_total=0; pos_hit=0; mrr_sum=0
abs_total=0; abs_ok=0
miss_recovered=0; miss_total=0
echo "=== hybrid-eval (Recall@$K, heavy tier: BM25 ∪ dense -> rerank) over $ROOT/.iroha/index.ndjson ==="
printf '%-52s %-8s %s\n' "query" "result" "rank/expected"
while IFS='|' read -r query expect; do
  case "$query" in ''|'#'*) continue ;; esac
  ids=$(iroha_recall_local "$ROOT" "$query" "$K" 2>/dev/null | jq -r 'select(.id)|.id')
  is_bm25_miss=0
  case "$BM25_MISSES" in *"$query"*) is_bm25_miss=1 ;; esac
  if [ "$expect" = "NONE" ]; then
    abs_total=$((abs_total + 1))
    if [ -z "$ids" ]; then
      abs_ok=$((abs_ok + 1)); printf '%-52s %-8s %s\n' "${query:0:50}" "ABSTAIN" "ok (no hit)"
    else
      printf '%-52s %-8s %s\n' "${query:0:50}" "LEAK" "got $(printf '%s' "$ids" | head -1)"
    fi
  else
    pos_total=$((pos_total + 1))
    [ "$is_bm25_miss" = 1 ] && miss_total=$((miss_total + 1))
    rank=$(printf '%s\n' "$ids" | grep -nxF "$expect" | head -1 | cut -d: -f1)
    if [ -n "$rank" ]; then
      pos_hit=$((pos_hit + 1)); mrr_sum=$(awk -v s="$mrr_sum" -v r="$rank" 'BEGIN{printf "%.4f", s + 1/r}')
      tag="HIT"; [ "$is_bm25_miss" = 1 ] && { tag="RECOVER"; miss_recovered=$((miss_recovered + 1)); }
      printf '%-52s %-8s %s\n' "${query:0:50}" "$tag" "rank $rank"
    else
      printf '%-52s %-8s %s\n' "${query:0:50}" "MISS" "expected ${expect:0:12}… not in top$K"
    fi
  fi
done < "$GOLDEN_FILE"

# SAME-VOCABULARY soft negatives (REPORTED, not gated). These prompts share the corpus's software
# vocabulary but ask about something iroha has NO decision on (how to write bash tests, upload an
# image…), so the only "match" is a wrong nearest neighbour. Measured 2026: NO local signal (BM25
# score, dense rank, BM25∩dense agreement, or the cross-encoder's low end) separates these from a
# real-but-terse match like "連結: relation でなく URL" — they are genuinely close in every space.
# iroha's documented stance (recall-eval.sh) is recall-first: hook hits are advisory ("verify"), so
# a same-vocab leak is low-harm context noise, not a wrong action, and the floor is intentionally
# NOT raised to suppress it at recall's expense. We therefore REPORT the soft-leak rate (so the
# precision/recall trade-off is visible, never hidden like the old veto tier's silent recall loss)
# but do not fail on it. Cross-domain abstention above IS gated — a true off-domain leak is a bug.
SOFT_NEG="Notionに画像をアップロードする方法を教えて
bashスクリプトのテストをどう書くか
jqでJSONをパースする方法
gitのブランチ戦略を決めたい"
soft_total=0; soft_quiet=0
while IFS= read -r q; do
  [ -z "$q" ] && continue
  soft_total=$((soft_total + 1))
  got=$(iroha_recall_local "$ROOT" "$q" "$K" 2>/dev/null | jq -r 'select(.id)|.title' | head -1)
  if [ -z "$got" ]; then soft_quiet=$((soft_quiet + 1)); fi
done <<< "$SOFT_NEG"

recall_pct=$(awk -v h="$pos_hit" -v t="$pos_total" 'BEGIN{printf "%d", (t? 100*h/t : 100)}')
abstain_pct=$(awk -v h="$abs_ok" -v t="$abs_total" 'BEGIN{printf "%d", (t? 100*h/t : 100)}')
mrr=$(awk -v s="$mrr_sum" -v t="$pos_total" 'BEGIN{printf "%.3f", (t? s/t : 0)}')
echo "---"
echo "same-vocab soft negatives quiet: $soft_quiet/$soft_total (reported only — recall-first, low-harm advisory)"
echo "Recall@$K = $pos_hit/$pos_total ($recall_pct%) · MRR = $mrr · Abstention = $abs_ok/$abs_total ($abstain_pct%) · BM25-miss recovered = $miss_recovered/$miss_total"

# Gates: abstention must stay perfect; recall must beat the BM25 baseline (13/15=86%) AND the dense
# lane must recover at least one BM25 candidate-generation miss (else hybrid earns nothing).
RECALL_THRESHOLD=86
fail=0
[ "$abstain_pct" -lt 100 ] && { echo "FAIL: abstention below 100% (a false hit is the worst failure)"; fail=1; }
[ "$recall_pct" -lt "$RECALL_THRESHOLD" ] && { echo "FAIL: Recall@$K below baseline ${RECALL_THRESHOLD}%"; fail=1; }
[ "$miss_recovered" -lt 1 ] && { echo "FAIL: dense lane recovered no BM25 miss (hybrid earns nothing)"; fail=1; }
[ "$fail" = 0 ] && echo "PASS: hybrid recovers $miss_recovered/$miss_total BM25 misses, abstention intact, no recall regression"
exit "$fail"
