#!/usr/bin/env bash
# recall-eval.sh — quality oracle for the local recall stage (scripts/_lib/search.sh).
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
set -u

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SEARCH="$(dirname "$0")/../scripts/_lib/search.sh"
K=3                                   # Recall@K — how many hits the hook would surface
MINSCORE="${IROHA_RECALL_MINSCORE:-1.2}"   # the production relevance floor (keep in sync w/ hook)
RECALL_THRESHOLD=80                   # require Recall@K >= 80%
ABSTAIN_THRESHOLD=100                 # require 100% honest abstention (a false hit is the worst failure)

# Golden set. One case per line: "<query>|<expected-page-id>"; expected id "NONE" = must abstain.
# Queries are paraphrases a developer would actually type (NOT the decision's own words), so this
# measures real recall, not echo. IDs are this repo's real Decision/Session pages.
read -r -d '' GOLDEN <<'EOF'
Notionの認証はAPIトークンが必要か|389822c6-938a-8137-824d-e4883efdbcf5
SessionとDecisionの連結にrelationを使うべきか|389822c6-938a-812a-86fc-f709b3428ec2
compactした後に会話を復元したい|38a822c6-938a-8159-8bca-c1edc602bb62
トランスクリプト抽出はbashとClaudeのどちらでやる|389822c6-938a-811c-9f41-e8dba15ef28f
リコールの設計方針はどうする|38a822c6-938a-81af-a4ab-c38c9f533b07
会話ログの全文はどこに保存する|38a822c6-938a-8175-8a6d-ece0145279ad
メモリの全件列挙はどうやる|38a822c6-938a-8167-98c2-fd940cb1dd06
StateをローカルにミラーするのはなぜJIT|389822c6-938a-81ef-829e-c0f6b1bc2b91
configure nginx reverse proxy with tls termination|NONE
optimize the react component re-rendering performance|NONE
terraform provider configuration for gcp networking|NONE
EOF

pos_total=0; pos_hit=0; mrr_sum=0
abs_total=0; abs_ok=0
echo "=== recall-eval (Recall@$K, MINSCORE=$MINSCORE) over $ROOT/.iroha/index.ndjson ==="
printf '%-52s %-8s %s\n' "query" "result" "rank/expected"
while IFS='|' read -r query expect; do
  [ -z "$query" ] && continue
  ids=$(bash "$SEARCH" "$ROOT" "$query" "" "$K" "$MINSCORE" 2>/dev/null | jq -r '.id')
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
echo "Recall@$K = $pos_hit/$pos_total ($recall_pct%) · MRR = $mrr · Abstention = $abs_ok/$abs_total ($abstain_pct%)"
fail=0
[ "$recall_pct" -lt "$RECALL_THRESHOLD" ] && { echo "FAIL: Recall@$K below ${RECALL_THRESHOLD}%"; fail=1; }
[ "$abstain_pct" -lt "$ABSTAIN_THRESHOLD" ] && { echo "FAIL: abstention below ${ABSTAIN_THRESHOLD}%"; fail=1; }
[ "$fail" = 0 ] && echo "PASS: recall quality thresholds met"
exit "$fail"
