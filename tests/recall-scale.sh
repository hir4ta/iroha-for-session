#!/usr/bin/env bash
# recall-scale.sh — proves local BM25 recall (scripts/_lib/search.sh) and the enumeration
# index still behave at "hundreds of sessions" scale, retiring the long-carried "does recall
# hold up as the memory grows?" risk with a MEASURED test instead of a vibe.
#
# selftest.sh proves the search mechanics on a handful of rows; recall-eval.sh proves quality
# on the real ~20-row index. This proves the two scale-sensitive properties on a synthetic
# large corpus (N≈320: a few known needles among hundreds of plausible distractors that share
# filler vocabulary):
#   1. ranking      — each needle's paraphrase query surfaces THAT needle in the top-K, above
#                     the production floor, despite 300+ competing rows (BM25 idf must keep a
#                     rare, on-topic term outranking common filler);
#   2. abstention   — an unrelated query still injects nothing (no false positive at scale);
#   3. enumeration  — index.sh list returns the COMPLETE set (the completeness primitive audit
#                     /dedup rely on must not degrade with size);
#   4. latency      — a full search finishes within the UserPromptSubmit hook timeout, so
#                     proactive recall never blocks a prompt even at scale.
# Run: bash tests/recall-scale.sh; echo $?   (0 = scale thresholds met)
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
SEARCH="$HERE/../scripts/_lib/search.sh"
# shellcheck disable=SC1091 # dynamic source path; the file exists at runtime
. "$HERE/../scripts/_lib/index.sh"
K=3
MINSCORE="${IROHA_RECALL_MINSCORE:-1.2}"   # production relevance floor (keep in sync with hook)
TIMEOUT_S=5                                # the UserPromptSubmit hook timeout (hooks/hooks.json)
DISTRACTORS=315                            # plausible-but-irrelevant rows surrounding the needles

command -v jq >/dev/null 2>&1 || { echo "recall-scale: jq is required" >&2; exit 1; }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/iroha-scale.XXXXXX")
mkdir -p "$ROOT/.iroha"
IDX="$ROOT/.iroha/index.ndjson"

# 315 distractor decisions sharing filler vocab (実装/調整/テスト). They must NOT outrank a
# needle whose distinctive terms (OAuth, relation, BM25, …) are rare across the corpus and so
# carry high idf — this is exactly the "many similar rows" stress scale was feared to break.
i=1
while [ "$i" -le "$DISTRACTORS" ]; do
  printf '{"type":"decision","id":"dec-%d","topic":"機能%d","status":"Active","date":"2026-01-01","title":"機能%d: 実装と調整","project":"scaletest","text":"機能%d の実装・調整・テストを行った汎用的な作業ログ"}\n' "$i" "$i" "$i" "$i"
  i=$((i + 1))
done > "$IDX"

# 5 known needles with distinctive terms + the paraphrase a developer would actually type
# (NOT the row's own words), so this measures recall, not echo.
{
  printf '%s\n' '{"type":"decision","id":"ndl-auth","topic":"認証方式","status":"Active","date":"2026-06-25","title":"認証方式: OAuth一本","project":"scaletest","text":"API トークンを持たず Notion MCP の OAuth で認証を一本化する"}'
  printf '%s\n' '{"type":"decision","id":"ndl-link","topic":"連結方式","status":"Active","date":"2026-06-25","title":"連結方式: URLプロパティ","project":"scaletest","text":"relation は書き込みバグがあるため URL プロパティでページを連結する"}'
  printf '%s\n' '{"type":"decision","id":"ndl-recall","topic":"検索方式","status":"Active","date":"2026-06-25","title":"検索方式: ローカルBM25","project":"scaletest","text":"毎回の LLM 呼び出しを避けローカルの BM25 で関連を先出しする"}'
  printf '%s\n' '{"type":"session","id":"ndl-compact","topic":"","status":"Complete","date":"2026-06-25","title":"2026-06-25 — 圧縮復帰","project":"scaletest","text":"compact の後に会話を transcript から再注入してスレッドを復元する"}'
  printf '%s\n' '{"type":"decision","id":"ndl-extract","topic":"抽出方式","status":"Active","date":"2026-06-25","title":"抽出方式: pure bash","project":"scaletest","text":"決定論抽出は bash で行い知性は Claude が担う"}'
} >> "$IDX"

total=$(grep -c . "$IDX")
pass=0; fail=0
echo "=== recall-scale (N=$total rows, Recall@$K, MINSCORE=$MINSCORE, timeout=${TIMEOUT_S}s) ==="

check_needle() { # check_needle <query> <expected-id>
  local q="$1" want="$2" rank
  rank=$(bash "$SEARCH" "$ROOT" "$q" "" "$K" "$MINSCORE" 2>/dev/null | jq -r '.id' | grep -nxF "$want" | head -1 | cut -d: -f1)
  if [ -n "$rank" ]; then
    printf '  PASS  needle "%s" -> rank %s\n' "$q" "$rank"; pass=$((pass + 1))
  else
    printf '  FAIL  needle "%s" -> %s not in top%d among %d rows\n' "$q" "$want" "$K" "$total"; fail=$((fail + 1))
  fi
}

check_needle "認証にトークンは必要か"             ndl-auth
check_needle "ページの連結にrelationを使うべきか"   ndl-link
check_needle "関連の先出しはどう実装する"           ndl-recall
check_needle "compactした後に会話を戻したい"        ndl-compact
check_needle "抽出はbashとClaudeどちらでやる"       ndl-extract

# abstention at scale: an unrelated query must inject nothing (no false-positive at size).
abs=$(bash "$SEARCH" "$ROOT" "deploy the kubernetes cluster with terraform on aws" "" "$K" "$MINSCORE" 2>/dev/null)
if [ -z "$abs" ]; then printf '  PASS  abstain on unrelated query\n'; pass=$((pass + 1))
else printf '  FAIL  abstain leaked: %s\n' "$(printf '%s' "$abs" | head -1)"; fail=$((fail + 1)); fi

# enumeration completeness at scale: index.sh list returns every row.
listed=$(iroha_index_list "$ROOT" | grep -c .)
if [ "$listed" = "$total" ]; then printf '  PASS  enumeration complete (%s/%s)\n' "$listed" "$total"; pass=$((pass + 1))
else printf '  FAIL  enumeration dropped rows (%s/%s)\n' "$listed" "$total"; fail=$((fail + 1)); fi

# latency: a full search must finish within the hook timeout even at scale. SECONDS (whole
# seconds, portable — no GNU `date +%N`, no `timeout` binary, both intentionally avoided) is
# coarse but exactly the right granularity against a 5s ceiling: it catches a catastrophic
# slowdown without sub-second flakiness on a loaded CI runner.
t0=$SECONDS
bash "$SEARCH" "$ROOT" "認証 連結 検索 抽出 圧縮 機能" "" "$K" "$MINSCORE" >/dev/null 2>&1
el=$((SECONDS - t0))
if [ "$el" -lt "$TIMEOUT_S" ]; then printf '  PASS  search latency %ss < %ss (hook timeout)\n' "$el" "$TIMEOUT_S"; pass=$((pass + 1))
else printf '  FAIL  search latency %ss >= %ss (would time out the hook)\n' "$el" "$TIMEOUT_S"; fail=$((fail + 1)); fi

rm -rf "$ROOT"
echo "--- result: $pass passed, $fail failed ---"
[ "$fail" -eq 0 ]
