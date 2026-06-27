#!/usr/bin/env bash
# recall-eval.sh — quality oracle for the local recall stage (scripts/_lib/search.ts).
#
# selftest.sh proves the search MECHANICS (tokenization, status weight, abstention) on synthetic
# fixtures. This proves the search QUALITY on the project's REAL index: a hand-labeled golden set
# of realistic developer prompts paired with the decision/session they should surface, plus
# abstention prompts that must surface nothing. It reports Recall@k, MRR, and abstention accuracy,
# and exits non-zero if they fall below threshold — so a recall regression (a tokenizer change, a
# bad floor) is caught, and "does the memory get more useful as it grows?" becomes a measured
# curve instead of a vibe (LongMemEval's abilities: retrieval, knowledge-update, abstention).
#
# It runs against <root>/.iroha/index.ndjson (default: this repo). Re-label the golden set when
# the index changes materially. Run: bash tests/recall-eval.sh; echo $?   (0 = thresholds met)
#
# KNOWN LIMITATION (abstention is scoped, not absolute). The negatives here are CROSS-DOMAIN
# (different language AND topic), which a pure-lexical pass abstains on cleanly (no shared CJK
# bigram -> score 0). But an off-topic prompt that shares the corpus's *software* vocabulary
# (e.g. "Postgresのインデックス設計を最適化" matches 設計/最適/インデ…) can clear the floor and
# leak a hit — and neither a higher floor nor a coverage gate separates it from a real paraphrase
# (their score/coverage distributions overlap; measured 2026-06-25). This is an inherent limit of
# lexical recall on a small, single-domain corpus; the proper fix is a local SEMANTIC stage, which
# is deliberately deferred (YAGNI). The harm is low: hook injections are labelled advisory
# ("possibly relevant; verify"), so a leak is context noise, not a wrong action, and /iroha:recall
# (semantic) + human judgement filter it. The floor is intentionally NOT raised — that would trade
# away real recall (the north-star value) to suppress low-harm noise. So "abstention" below is
# reported as CROSS-DOMAIN abstention; same-software-vocabulary precision is a known soft spot.
set -u

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SEARCH="$(dirname "$0")/../scripts/_lib/search.ts"
K=3                                   # Recall@K — how many hits the hook would surface
MINSCORE="${IROHA_RECALL_MINSCORE:-1.2}"   # the production relevance floor (keep in sync w/ hook)
RECALL_THRESHOLD=80                   # require Recall@K >= 80%
ABSTAIN_THRESHOLD=100                 # require 100% honest abstention (a false hit is the worst failure)

# Golden set. One case per line: "<query>|<expected-page-id>"; expected id "NONE" = must abstain.
# Queries are paraphrases a developer would actually type (NOT the decision's own words), so this
# measures real recall, not echo. IDs are this repo's real Decision/Session pages. The last four
# positives are SESSION-seeking ("have we done X before?") so this set measures SESSION recall too,
# not just decisions — closing the blind spot that the set was previously all-decision (a measured
# re-check found session recall actually healthy: distinctive-work queries rank 1-2; these lock it
# against regression).
# Single source of truth: tests/golden-recall.txt (shared with hybrid-eval.sh). Skip comments/blanks.
GOLDEN="$(grep -vE '^[[:space:]]*(#|$)' "$(dirname "$0")/golden-recall.txt")"

pos_total=0; pos_hit=0; mrr_sum=0
abs_total=0; abs_ok=0
echo "=== recall-eval (Recall@$K, MINSCORE=$MINSCORE) over $ROOT/.iroha/index.ndjson ==="
printf '%-52s %-8s %s\n' "query" "result" "rank/expected"
while IFS='|' read -r query expect; do
  [ -z "$query" ] && continue
  ids=$(bun "$SEARCH" "$ROOT" "$query" "" "$K" "$MINSCORE" 2>/dev/null | jq -r '.id')
  if [ "$expect" = "NONE" ]; then
    abs_total=$((abs_total + 1))
    if [ -z "$ids" ]; then
      abs_ok=$((abs_ok + 1)); printf '%-52s %-8s %s\n' "${query:0:50}" "ABSTAIN" "ok (no hit)"
    else
      printf '%-52s %-8s %s\n' "${query:0:50}" "LEAK" "got $(printf '%s' "$ids" | head -1)"
    fi
  else
    pos_total=$((pos_total + 1))
    rank=$(printf '%s\n' "$ids" | grep -nxF "$expect" | head -1 | cut -d: -f1)
    if [ -n "$rank" ]; then
      pos_hit=$((pos_hit + 1)); mrr_sum=$(awk -v s="$mrr_sum" -v r="$rank" 'BEGIN{printf "%.4f", s + 1/r}')
      printf '%-52s %-8s %s\n' "${query:0:50}" "HIT" "rank $rank"
    else
      printf '%-52s %-8s %s\n' "${query:0:50}" "MISS" "expected ${expect:0:12}… not in top$K"
    fi
  fi
done <<< "$GOLDEN"

recall_pct=$(awk -v h="$pos_hit" -v t="$pos_total" 'BEGIN{printf "%d", (t? 100*h/t : 100)}')
abstain_pct=$(awk -v h="$abs_ok" -v t="$abs_total" 'BEGIN{printf "%d", (t? 100*h/t : 100)}')
mrr=$(awk -v s="$mrr_sum" -v t="$pos_total" 'BEGIN{printf "%.3f", (t? s/t : 0)}')
echo "---"
echo "Recall@$K = $pos_hit/$pos_total ($recall_pct%) · MRR = $mrr · Abstention (cross-domain) = $abs_ok/$abs_total ($abstain_pct%)"
fail=0
[ "$recall_pct" -lt "$RECALL_THRESHOLD" ] && { echo "FAIL: Recall@$K below ${RECALL_THRESHOLD}%"; fail=1; }
[ "$abstain_pct" -lt "$ABSTAIN_THRESHOLD" ] && { echo "FAIL: abstention below ${ABSTAIN_THRESHOLD}%"; fail=1; }
[ "$fail" = 0 ] && echo "PASS: recall quality thresholds met"
exit "$fail"
