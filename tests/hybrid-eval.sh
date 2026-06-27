#!/usr/bin/env bash
# hybrid-eval.sh — quality oracle for the HEAVY recall tier (BM25 ∪ dense -> cross-encoder rerank).
#
# recall-eval.sh measures the FREE tier (pure-jq BM25). This measures the opt-in HEAVY tier on the
# SAME golden set (tests/golden-recall.txt), through the exact production code path
# (scripts/_lib/recall.sh :: iroha_recall_local), so the eval reflects what a user with the models
# installed actually gets. It reports Recall@k, MRR and abstention, and runs the FREE tier (pure
# BM25) for the SAME queries so it can prove the heavy tier's actual guarantee — MONOTONICITY: the
# dense lane only ADDS candidates, BM25 hits are sacrosanct, so the heavy path must never drop a BM25
# hit (the recall regression the old VETO tier silently caused; this eval is its guard). Which golden
# queries are "BM25 misses the dense lane recovers" is DERIVED from comparing the two tiers per query
# — not a hardcoded list (that was a second source of truth alongside golden-recall.txt, and it
# drifted dead on the last index re-base). Recovery is REPORTED, not gated: on a terse-Japanese corpus
# the cross-encoder scores real-but-terse matches ~0 (below the promote threshold), so 0 recovery is
# the documented, expected reality, not a regression.
#
# It SKIPs (exit 0, no failure) when the opt-in models are not installed, exactly like
# rerank-eval.sh, so a fresh CI checkout without the ~hundreds-of-MB models is green. Run the real
# thing with the models present:  IROHA_MODEL_DIR=$HOME/.iroha/models bash tests/hybrid-eval.sh
set -u

ROOT="${IROHA_EVAL_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PR="$(cd "$(dirname "$0")/.." && pwd)"
GOLDEN_FILE="$(dirname "$0")/golden-recall.txt"
K=3

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
bm_hit=0; recovered=0; regressed=0
echo "=== hybrid-eval (Recall@$K, heavy tier: BM25 ∪ dense -> rerank) over $ROOT/.iroha/index.ndjson ==="
printf '%-52s %-8s %s\n' "query" "result" "rank/expected"
while IFS='|' read -r query expect; do
  case "$query" in ''|'#'*) continue ;; esac
  # HEAVY = the production heavy path (FORCE_HEAVY=1 exported). FREE = pure BM25, the EXACT free-tier
  # call recall.sh makes. Running both for the same query lets recovery/regression be DERIVED from the
  # data (no hardcoded "which queries are hard" list to drift from golden-recall.txt).
  heavy_ids=$(iroha_recall_local "$ROOT" "$query" "$K" 2>/dev/null | jq -r 'select(.id)|.id')
  free_ids=$(bash "$PR/scripts/_lib/search.sh" "$ROOT" "$query" "" "$K" "${IROHA_RECALL_MINSCORE:-1.2}" 2>/dev/null | jq -r 'select(.id)|.id')
  if [ "$expect" = "NONE" ]; then
    abs_total=$((abs_total + 1))
    if [ -z "$heavy_ids" ]; then
      abs_ok=$((abs_ok + 1)); printf '%-52s %-8s %s\n' "${query:0:50}" "ABSTAIN" "ok (no hit)"
    else
      printf '%-52s %-8s %s\n' "${query:0:50}" "LEAK" "got $(printf '%s' "$heavy_ids" | head -1)"
    fi
  else
    pos_total=$((pos_total + 1))
    hrank=$(printf '%s\n' "$heavy_ids" | grep -nxF "$expect" | head -1 | cut -d: -f1)
    frank=$(printf '%s\n' "$free_ids"  | grep -nxF "$expect" | head -1 | cut -d: -f1)
    [ -n "$frank" ] && bm_hit=$((bm_hit + 1))
    if [ -n "$hrank" ]; then
      pos_hit=$((pos_hit + 1)); mrr_sum=$(awk -v s="$mrr_sum" -v r="$hrank" 'BEGIN{printf "%.4f", s + 1/r}')
      if [ -z "$frank" ]; then
        recovered=$((recovered + 1)); tag="RECOVER"   # BM25 missed it; dense+rerank promoted it back
      else
        tag="HIT"
      fi
      printf '%-52s %-8s %s\n' "${query:0:50}" "$tag" "rank $hrank"
    else
      # A heavy MISS of something BM25 HIT is a MONOTONICITY REGRESSION — the heavy tier dropped a BM25
      # hit (the exact failure the old veto tier caused; this eval exists to catch it).
      [ -n "$frank" ] && regressed=$((regressed + 1))
      note="expected ${expect:0:12}… not in top$K"
      [ -n "$frank" ] && note="REGRESSION: BM25 had it at rank $frank, heavy dropped it"
      printf '%-52s %-8s %s\n' "${query:0:50}" "MISS" "$note"
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
bm_pct=$(awk -v h="$bm_hit" -v t="$pos_total" 'BEGIN{printf "%d", (t? 100*h/t : 100)}')
abstain_pct=$(awk -v h="$abs_ok" -v t="$abs_total" 'BEGIN{printf "%d", (t? 100*h/t : 100)}')
mrr=$(awk -v s="$mrr_sum" -v t="$pos_total" 'BEGIN{printf "%.3f", (t? s/t : 0)}')
echo "---"
echo "same-vocab soft negatives quiet: $soft_quiet/$soft_total (reported only — recall-first, low-harm advisory)"
echo "Recall@$K = $pos_hit/$pos_total ($recall_pct%) · BM25 baseline = $bm_hit/$pos_total ($bm_pct%) · recovered = $recovered · regressed = $regressed · MRR = $mrr · Abstention = $abs_ok/$abs_total ($abstain_pct%)"

# Gates. The heavy tier's GUARANTEE (architecture.md) is MONOTONICITY: hybrid recall >= BM25 recall —
# the dense lane only ADDS candidates, BM25 hits are sacrosanct, so the heavy path must never drop a
# BM25 hit. `regressed` counts exactly that violation per query (stronger than comparing aggregate
# percentages, which a recovery could mask). RECOVERY is a corpus-dependent BONUS, REPORTED not gated:
# on this terse-Japanese corpus the cross-encoder scores real-but-terse matches ~0 (< promote
# threshold), so 0 recovery is the documented, expected reality — gating it would demand an outcome
# the promote-not-veto design does not promise (same stance as the soft-negative leak above).
RECALL_THRESHOLD=86
fail=0
[ "$abstain_pct" -lt 100 ] && { echo "FAIL: abstention below 100% (a false hit is the worst failure)"; fail=1; }
[ "$recall_pct" -lt "$RECALL_THRESHOLD" ] && { echo "FAIL: Recall@$K below baseline ${RECALL_THRESHOLD}%"; fail=1; }
[ "$regressed" -gt 0 ] && { echo "FAIL: heavy tier dropped $regressed BM25 hit(s) — monotonicity violated (hybrid recall < BM25 recall)"; fail=1; }
[ "$fail" = 0 ] && echo "PASS: hybrid recall >= BM25 (no regression), abstention 100%; recovered $recovered BM25 miss(es) on this corpus"
exit "$fail"
