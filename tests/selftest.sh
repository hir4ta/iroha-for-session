#!/usr/bin/env bash
# iroha-for-notion selftest — behavioral oracle for deterministic extraction.
# Runs scripts/extract.sh against a synthetic transcript fixture and asserts the views
# save-session depends on (files / commands / meta) are correct — including tolerance of
# truncated / malformed transcript lines. Also covers config and the SessionStart hook.
# Run: bash tests/selftest.sh; echo $?   (0 = ALL PASS)
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
EXTRACT="$HERE/../scripts/extract.sh"
FIX="$HERE/fixtures/sample.jsonl"

pass=0
fail=0
# has <name> <needle> <haystack> — pass if haystack contains needle.
has() {
  if printf '%s' "$3" | grep -qF -- "$2"; then
    printf '  PASS  %s\n' "$1"
    pass=$((pass + 1))
  else
    printf '  FAIL  %s (missing: %s)\n' "$1" "$2"
    fail=$((fail + 1))
  fi
}
# hasnt <name> <needle> <haystack> — pass if haystack does NOT contain needle.
hasnt() {
  if printf '%s' "$3" | grep -qF -- "$2"; then
    printf '  FAIL  %s (leaked: %s)\n' "$1" "$2"
    fail=$((fail + 1))
  else
    printf '  PASS  %s\n' "$1"
    pass=$((pass + 1))
  fi
}
# eq <name> <expected> <got>
eq() {
  if [ "$3" = "$2" ]; then
    printf '  PASS  %s\n' "$1"
    pass=$((pass + 1))
  else
    printf '  FAIL  %s exp=[%s] got=[%s]\n' "$1" "$2" "$3"
    fail=$((fail + 1))
  fi
}

echo "=== extract meta (the view save-session depends on) ==="
meta=$(bash "$EXTRACT" meta "$FIX")
eq meta-valid-json "ok" "$(printf '%s' "$meta" | jq -e . >/dev/null 2>&1 && echo ok || echo bad)"
has meta-title "Add login endpoint" "$meta"
has meta-sessionid "sessionId" "$meta"

echo "=== extract files (deduped) ==="
files=$(bash "$EXTRACT" files "$FIX")
has files-path "src/login.ts" "$files"
eq files-dedup "1" "$(printf '%s\n' "$files" | grep -c 'src/login.ts')"

echo "=== extract commands (first line only) ==="
cmds=$(bash "$EXTRACT" commands "$FIX")
has cmd-bash "npm test" "$cmds"
hasnt cmd-firstline-only "echo done" "$cmds"

echo "=== extract prompts (human's real messages — the You-anchor) ==="
prompts=$(bash "$EXTRACT" prompts "$FIX")
has prompts-human "Please add a login endpoint" "$prompts"
hasnt prompts-no-toolresult "FILE WRITTEN" "$prompts"
hasnt prompts-no-tasknotif "NOISE-TASKNOTIF" "$prompts"
hasnt prompts-no-caveat "NOISE-CAVEAT" "$prompts"

echo "=== extract stats (metrics dashboard numbers) ==="
stats=$(bash "$EXTRACT" stats "$FIX")
eq stats-valid-json "ok" "$(printf '%s' "$stats" | jq -e . >/dev/null 2>&1 && echo ok || echo bad)"
eq stats-userturns "1" "$(printf '%s' "$stats" | jq -r '.userTurns')"
eq stats-files "1" "$(printf '%s' "$stats" | jq -r '.filesEdited')"
eq stats-duration "5" "$(printf '%s' "$stats" | jq -r '.durationMin')"

echo "=== extract tools (per-tool tally) ==="
tools=$(bash "$EXTRACT" tools "$FIX")
has tools-bash "Bash" "$tools"

echo "=== extract chat (cleaned full chat, no noise) ==="
chat=$(bash "$EXTRACT" chat "$FIX")
has chat-you "Please add a login endpoint" "$chat"
has chat-claude "the endpoint is added" "$chat"
hasnt chat-no-thinking "SECRET THOUGHTS" "$chat"
hasnt chat-no-toolresult "FILE WRITTEN" "$chat"
hasnt chat-no-sidechain "SIDECHAIN" "$chat"
hasnt chat-no-caveat "NOISE-CAVEAT" "$chat"

echo "=== extract tolerates truncated / malformed lines ==="
BROKEN=$(mktemp "${TMPDIR:-/tmp}/iroha-broken.XXXXXX")
cat "$FIX" >"$BROKEN"
printf 'GARBAGE-NOT-JSON\n{"type":"assistant","truncated-no-close\n' >>"$BROKEN"
bfiles=$(bash "$EXTRACT" files "$BROKEN")
bec=$?
eq broken-files-exit0 "0" "$bec"
has broken-files-survives "src/login.ts" "$bfiles"
bmeta=$(bash "$EXTRACT" meta "$BROKEN")
eq broken-meta-valid-json "ok" "$(printf '%s' "$bmeta" | jq -e . >/dev/null 2>&1 && echo ok || echo bad)"
has broken-meta-title "Add login endpoint" "$bmeta"
rm -f "$BROKEN"

echo "=== config helper (roundtrip, self-heal, isolated dir) ==="
IROHA_CONFIG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/iroha-cfg.XXXXXX")"
export IROHA_CONFIG_DIR
# shellcheck disable=SC1091 # dynamic source path; the file exists at runtime
. "$HERE/../scripts/_lib/config.sh"
iroha_config_set session_db_id "DB123"
eq config-set-get "DB123" "$(iroha_config_get session_db_id)"
eq config-missing-empty "" "$(iroha_config_get nonexistent_key)"
iroha_config_set_state_page "/repo/foo" "PAGE9"
eq config-state-roundtrip "PAGE9" "$(iroha_config_get_state_page "/repo/foo")"
eq config-state-missing "" "$(iroha_config_get_state_page "/repo/bar")"
# a corrupt config.json self-heals instead of locking up every get/set
printf 'GARBAGE' >"$IROHA_CONFIG_DIR/config.json"
eq config-self-heal-get "" "$(iroha_config_get session_db_id)"
iroha_config_set session_db_id "DB2"
eq config-self-heal-set "DB2" "$(iroha_config_get session_db_id)"
rm -rf "$IROHA_CONFIG_DIR"

echo "=== session-start hook (state injection + save reminder) ==="
HOOKHOME=$(mktemp -d "${TMPDIR:-/tmp}/iroha-home.XXXXXX")
HOOKDATA=$(mktemp -d "${TMPDIR:-/tmp}/iroha-data.XXXXXX")
PROJ=$(mktemp -d "${TMPDIR:-/tmp}/iroha-proj.XXXXXX")   # repo root; State mirror at $PROJ/.iroha/state.md
HASH=$(printf '%s' "$PROJ" | sed 's#/#-#g')
mkdir -p "$HOOKHOME/.claude/projects/$HASH" "$PROJ/.iroha"
: >"$HOOKHOME/.claude/projects/$HASH/old.jsonl"
printf 'STATE-CONTENT-XYZ' >"$PROJ/.iroha/state.md"
run_hook() {
  printf '{"cwd":"%s","session_id":"cur"}' "$PROJ" |
    CLAUDE_PLUGIN_ROOT="$HERE/.." IROHA_CONFIG_DIR="$HOOKDATA" HOME="$HOOKHOME" \
      bash "$HERE/../hooks/session-start.sh"
}
out=$(run_hook)
has hook-injects-state "STATE-CONTENT-XYZ" "$out"
has hook-reminds-unsaved "not saved" "$out"
has hook-open-count "Open items carried over" "$out"
has hook-json-shape "hookSpecificOutput" "$out"
mkdir -p "$HOOKDATA/saved" && : >"$HOOKDATA/saved/old"
hasnt hook-no-remind-when-saved "not saved" "$(run_hook)"
# compaction restart (source=compact) re-injects THIS session's conversation from its transcript
printf '{"type":"user","isSidechain":false,"message":{"role":"user","content":"COMPACT-RECAP-PROMPT please"}}\n' >"$HOOKHOME/.claude/projects/$HASH/cur.jsonl"
cout=$(printf '{"cwd":"%s","session_id":"cur","source":"compact"}' "$PROJ" |
  CLAUDE_PLUGIN_ROOT="$HERE/.." IROHA_CONFIG_DIR="$HOOKDATA" HOME="$HOOKHOME" \
    bash "$HERE/../hooks/session-start.sh")
has hook-compact-recap "re-injected after compaction" "$cout"
has hook-compact-prompt "COMPACT-RECAP-PROMPT" "$cout"
rm -f "$HOOKHOME/.claude/projects/$HASH/cur.jsonl"
rm -f "$PROJ/.iroha/state.md" "$HOOKHOME/.claude/projects/$HASH/old.jsonl"
eq hook-silent-when-empty "" "$(run_hook)"
# missing CLAUDE_PLUGIN_ROOT must exit 0 silently, not crash under set -u
env -u CLAUDE_PLUGIN_ROOT HOME="$HOOKHOME" bash "$HERE/../hooks/session-start.sh" <<<'{"cwd":"/x","session_id":"y"}' >/dev/null 2>&1
eq hook-no-plugin-root-exit0 "0" "$?"
rm -rf "$HOOKHOME" "$HOOKDATA" "$PROJ"

echo "=== index (local enumeration: upsert by id, find-topic, list) ==="
IDXROOT=$(mktemp -d "${TMPDIR:-/tmp}/iroha-idx-root.XXXXXX")
# shellcheck disable=SC1091 # dynamic source path; the file exists at runtime
. "$HERE/../scripts/_lib/index.sh"
iroha_index_upsert "$IDXROOT" decision dec1 "linking" Active 2026-06-24 "linking: URL" demo
iroha_index_upsert "$IDXROOT" decision dec2 "runtime" Active 2026-06-24 "runtime: bash" demo
iroha_index_upsert "$IDXROOT" session ses1 "" Complete 2026-06-25 "2026-06-25 eval" demo
# upsert by id replaces in place: a status change must not duplicate the row
iroha_index_upsert "$IDXROOT" decision dec1 "linking" Superseded 2026-06-24 "linking: URL" demo
idxall=$(iroha_index_list "$IDXROOT")
eq index-no-dup-on-reupsert "1" "$(printf '%s\n' "$idxall" | grep -c '"id":"dec1"')"
eq index-status-replaced "Superseded" "$(iroha_index_find_topic "$IDXROOT" "linking" | jq -r '.status')"
# find-topic is case-insensitive on ASCII (the decision dedup key)
eq index-find-topic-ci "dec2" "$(iroha_index_find_topic "$IDXROOT" "RUNTIME" | jq -r '.id')"
eq index-find-topic-miss "" "$(iroha_index_find_topic "$IDXROOT" "missing-topic")"
eq index-list-decisions "2" "$(iroha_index_list "$IDXROOT" decision | grep -c '"type":"decision"')"
eq index-list-sessions "1" "$(iroha_index_list "$IDXROOT" session | grep -c '"type":"session"')"
eq index-valid-ndjson "ok" "$(iroha_index_list "$IDXROOT" | jq -e . >/dev/null 2>&1 && echo ok || echo bad)"
rm -rf "$IDXROOT"

echo "=== search (local BM25 recall: CJK bigram, text field, status weight, abstention) ==="
SROOT=$(mktemp -d "${TMPDIR:-/tmp}/iroha-search.XXXXXX")
mkdir -p "$SROOT/.iroha"
# Japanese decision/session rows in the real index shape (title + rationale/summary snippet).
{
  printf '%s\n' '{"type":"decision","id":"d1","topic":"連結","status":"Active","date":"2026-06-24","title":"連結: relation でなく URL","project":"demo","text":"relation は MCP 書き込みバグがあるので URL プロパティで Session と Decision をつなぐ"}'
  printf '%s\n' '{"type":"decision","id":"d2","topic":"Notion 連携","status":"Active","date":"2026-06-24","title":"Notion 連携: MCP 一本","project":"demo","text":"API トークンの二重セットアップを避けるため認証は Notion MCP の OAuth に統一する"}'
  printf '%s\n' '{"type":"decision","id":"d3","topic":"リコール","status":"Superseded","date":"2026-06-24","title":"リコール: ローカル grep","project":"demo","text":"ローカル grep で検索する旧方針"}'
  printf '%s\n' '{"type":"decision","id":"d4","topic":"リコール","status":"Active","date":"2026-06-25","title":"リコール: hybrid","project":"demo","text":"notion-search と index を融合して検索する"}'
  printf '%s\n' '{"type":"session","id":"s1","topic":"","status":"Complete","date":"2026-06-25","title":"2026-06-25 — 認証フローの設計","project":"demo","text":"OAuth の認証フローを設計した"}'
} >"$SROOT/.iroha/index.ndjson"
SEARCH="$HERE/../scripts/_lib/search.sh"
# CJK bigram tokenization: a Japanese query matches a Japanese title (空白splitなら潰れる)
eq search-cjk-bigram "d1" "$(bash "$SEARCH" "$SROOT" "URLで連結したい" decision 3 | head -1 | jq -r .id)"
# text-field enrichment: "APIトークン" appears ONLY in d2's rationale snippet, not its title —
# title-only matching would miss it; the text field surfaces it (the Q2 miss this fixes).
eq search-text-field "d2" "$(bash "$SEARCH" "$SROOT" "APIトークンは必要か" decision 3 | head -1 | jq -r .id)"
# status weight: same topic "リコール", Active (d4) must outrank Superseded (d3).
eq search-active-over-superseded "d4" "$(bash "$SEARCH" "$SROOT" "リコール" decision 3 | head -1 | jq -r .id)"
# English alnum token matches a snippet ("OAuth" only in s1's text).
has search-english-token "s1" "$(bash "$SEARCH" "$SROOT" "oauth flow" "" 3 | jq -r .id)"
# type filter: only sessions returned when type=session even though d2 also matches 認証.
eq search-type-filter "session" "$(bash "$SEARCH" "$SROOT" "認証" session 3 | jq -rs 'map(.type)|unique|join(",")')"
# abstention: a query with no token overlap returns nothing (no false-positive injection).
eq search-abstain "" "$(bash "$SEARCH" "$SROOT" "zzqqxx vvbbnn wwkkpp" "" 3)"
# output is valid JSON, descending by score.
eq search-valid-json "ok" "$(bash "$SEARCH" "$SROOT" "リコール 検索" "" 5 | jq -e . >/dev/null 2>&1 && echo ok || echo bad)"
eq search-desc-score "true" "$(bash "$SEARCH" "$SROOT" "リコール 検索 連結 認証" "" 5 | jq -s '[.[].score] as $s | $s==($s|sort|reverse)')"
rm -rf "$SROOT"

echo "=== recall-inject hook (local BM25 recall: gate, consent, cache, abstain, inject) ==="
RIDATA=$(mktemp -d "${TMPDIR:-/tmp}/iroha-ri-data.XXXXXX")
RIPROJ=$(mktemp -d "${TMPDIR:-/tmp}/iroha-ri-proj.XXXXXX")   # project root: index at $RIPROJ/.iroha/
RICACHE=$(mktemp -d "${TMPDIR:-/tmp}/iroha-ri-cache.XXXXXX")
IROHA_CONFIG_DIR="$RIDATA" bash "$HERE/../scripts/_lib/config.sh" set decisions_ds_id "DSID" >/dev/null
IROHA_CONFIG_DIR="$RIDATA" bash "$HERE/../scripts/_lib/config.sh" set session_ds_id "SSID" >/dev/null
IROHA_CONFIG_DIR="$RIDATA" bash "$HERE/../scripts/_lib/config.sh" set recall_enabled true >/dev/null
# a one-row local index: a Japanese decision the hook must surface for a matching prompt.
mkdir -p "$RIPROJ/.iroha"
printf '%s\n' '{"type":"decision","id":"389822c6-938a-812a-86fc-f709b3428ec2","topic":"連結","status":"Active","date":"2026-06-24","title":"連結: relation でなく URL","project":"demo","text":"MCP の relation 書き込みに既知バグがあるので URL プロパティで連結する"}' \
  >"$RIPROJ/.iroha/index.ndjson"
ri() {  # ri <prompt> <sid> [EXTRA_ENV=val ...]   (no claude/timeout — recall is pure-local now)
  local p="$1" s="$2"
  shift 2
  printf '{"prompt":"%s","session_id":"%s","cwd":"%s"}' "$p" "$s" "$RIPROJ" |
    env CLAUDE_PLUGIN_ROOT="$HERE/.." IROHA_CONFIG_DIR="$RIDATA" TMPDIR="$RICACHE" "$@" \
      bash "$HERE/../hooks/recall-inject.sh"
}
hp=$(ri "relationプロパティで連結すべきか検討したい" sid1)
has ri-inject-shape "hookSpecificOutput" "$hp"
has ri-inject-content "連結: relation でなく URL" "$hp"          # the matched decision's title
has ri-inject-url "notion.so/389822c6938a812a86fcf709b3428ec2" "$hp"  # reconstructed page URL
eq ri-cache-second-empty "" "$(ri "relationプロパティで連結すべきか検討したい" sid1)"
eq ri-gate-short "" "$(ri "hi there" sid2)"
eq ri-gate-slash "" "$(ri "/iroha:recall some topic here" sid3)"
# system / automation pseudo-turns must NOT trigger recall (observed live: a task-notification
# slipped the gate and injected an off-topic hit).
eq ri-gate-tasknotif "" "$(ri "<task-notification> an async agent just finished its work" sidT)"
eq ri-gate-sysreminder "" "$(ri "<system-reminder> background reference context, not a request" sidS)"
eq ri-disable "" "$(ri "relationプロパティで連結すべきか別セッションで" sidD IROHA_RECALL_DISABLE=1)"
# abstention: a substantive prompt with NO lexical match in the index injects nothing (no
# false-positive recall) — the cheap local stage stays silent rather than guess.
eq ri-abstain "" "$(ri "deploy the kubernetes cluster to the aws region" sid4)"
# relevance floor is tunable: an impossibly high MINSCORE drops even a real match.
eq ri-minscore-floor "" "$(ri "relationで連結する設計" sid8 IROHA_RECALL_MINSCORE=999)"
# not initialized: empty config -> degrade (no injection)
RIDATA2=$(mktemp -d "${TMPDIR:-/tmp}/iroha-ri-data2.XXXXXX")
eq ri-not-initialized "" "$(printf '{"prompt":"relationプロパティで連結すべきか","session_id":"sid5","cwd":"%s"}' "$RIPROJ" |
  env CLAUDE_PLUGIN_ROOT="$HERE/.." IROHA_CONFIG_DIR="$RIDATA2" TMPDIR="$RICACHE" \
    bash "$HERE/../hooks/recall-inject.sh")"
# consent gate: initialized but recall_enabled not set -> no injection (distribution-safe default)
RIDATA3=$(mktemp -d "${TMPDIR:-/tmp}/iroha-ri-data3.XXXXXX")
IROHA_CONFIG_DIR="$RIDATA3" bash "$HERE/../scripts/_lib/config.sh" set decisions_ds_id "DSID" >/dev/null
eq ri-gate-recall-disabled "" "$(printf '{"prompt":"relationプロパティで連結すべきか","session_id":"sid6","cwd":"%s"}' "$RIPROJ" |
  env CLAUDE_PLUGIN_ROOT="$HERE/.." IROHA_CONFIG_DIR="$RIDATA3" TMPDIR="$RICACHE" \
    bash "$HERE/../hooks/recall-inject.sh")"
# selfcheck (offline, no external round-trip): prerequisites present -> READY, exit 0.
sc=$(env CLAUDE_PLUGIN_ROOT="$HERE/.." IROHA_CONFIG_DIR="$RIDATA" \
  bash "$HERE/../hooks/recall-inject.sh" --selfcheck)
has ri-selfcheck-ready "READY" "$sc"
has ri-selfcheck-config "config initialized" "$sc"
# selfcheck must work when run by hand (no CLAUDE_PLUGIN_ROOT) by deriving root from $0
sc2=$(env -u CLAUDE_PLUGIN_ROOT IROHA_CONFIG_DIR="$RIDATA" \
  bash "$HERE/../hooks/recall-inject.sh" --selfcheck)
has ri-selfcheck-derives-root "READY" "$sc2"
rm -rf "$RIDATA" "$RIDATA2" "$RIDATA3" "$RIPROJ" "$RICACHE"

echo "=== state-lint (State body validator: escapes, missing sections, summary, real mirror) ==="
# shellcheck disable=SC1091 # dynamic source path; the file exists at runtime
. "$HERE/../scripts/_lib/state-lint.sh"
SLDIR=$(mktemp -d "${TMPDIR:-/tmp}/iroha-sl.XXXXXX")
# good: real newlines, a summary line, and the three required sections -> clean (exit 0).
printf '%s\n' '**Latest (2026-06-25):** did things.' '## Recent sessions' '- [x — y](u)' \
  '## Unfinished / Next' '- [ ] thing' '## Decisions' '- [Decisions DB](u)' >"$SLDIR/good.md"
eq state-lint-good "0" "$(iroha_state_lint "$SLDIR/good.md" >/dev/null 2>&1; echo $?)"
# bad: literal \n / \t escape leak on one line (the exact corruption that degraded a past State).
printf '%s' '**Latest:** a\nb\t## Recent sessions\n## Unfinished\n## Decisions' >"$SLDIR/escape.md"
eq state-lint-escape-fail "1" "$(iroha_state_lint "$SLDIR/escape.md" >/dev/null 2>&1; echo $?)"
has state-lint-escape-msg "escape sequence" "$(iroha_state_lint "$SLDIR/escape.md" 2>&1)"
# bad: degraded to a summary-only callout (no sections) -> fail.
printf '%s\n' '**Latest (2026-06-25):** only a summary, sections were dropped.' >"$SLDIR/summaryonly.md"
eq state-lint-summaryonly-fail "1" "$(iroha_state_lint "$SLDIR/summaryonly.md" >/dev/null 2>&1; echo $?)"
# bad: empty/missing file -> fail (never publish an empty State).
: >"$SLDIR/empty.md"
eq state-lint-empty-fail "1" "$(iroha_state_lint "$SLDIR/empty.md" >/dev/null 2>&1; echo $?)"
# the project's REAL committed mirror must pass — guards against false positives AND makes CI fail
# if a corrupt State is ever committed (the recurring rot class, now caught at green/push time).
eq state-lint-real-mirror "0" "$(iroha_state_lint "$HERE/../.iroha/state.md" >/dev/null 2>&1; echo $?)"
rm -rf "$SLDIR"

echo "=== result: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
