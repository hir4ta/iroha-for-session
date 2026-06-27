#!/usr/bin/env bash
# iroha-for-session selftest — behavioral oracle for deterministic extraction.
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
hasnt prompts-no-ismeta "NOISE-ISMETA" "$prompts"   # harness meta turn (isMeta) is not a You line
hasnt prompts-no-teammate "NOISE-TEAMMATE" "$prompts"  # a peer-agent (teammate-message) is not a You turn
hasnt prompts-no-compact "NOISE-COMPACT" "$prompts"    # an injected compaction summary is not a You turn

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
hasnt chat-no-ismeta "NOISE-ISMETA" "$chat"   # harness meta turn (isMeta) excluded from the chat too
hasnt chat-no-teammate "NOISE-TEAMMATE" "$chat"  # peer-agent (teammate-message) excluded from the chat
hasnt chat-no-compact "NOISE-COMPACT" "$chat"    # injected compaction summary excluded from the chat

echo "=== extract all (one-pass aggregate — must equal the individual views, no drift) ==="
all=$(bash "$EXTRACT" all "$FIX")
eq all-valid-json "ok" "$(printf '%s' "$all" | jq -e . >/dev/null 2>&1 && echo ok || echo bad)"
eq all-meta-eq     "$(bash "$EXTRACT" meta "$FIX" | jq -S .)"  "$(printf '%s' "$all" | jq -S .meta)"
eq all-stats-eq    "$(bash "$EXTRACT" stats "$FIX" | jq -S .)" "$(printf '%s' "$all" | jq -S .stats)"
eq all-files-eq    "$(bash "$EXTRACT" files "$FIX")"    "$(printf '%s' "$all" | jq -r '.files[]')"
eq all-commands-eq "$(bash "$EXTRACT" commands "$FIX")" "$(printf '%s' "$all" | jq -r '.commands[]')"
eq all-prompts-eq  "$(bash "$EXTRACT" prompts "$FIX")"  "$(printf '%s' "$all" | jq -r '.prompts[]')"
eq all-tools-eq    "$(bash "$EXTRACT" tools "$FIX")"    "$(printf '%s' "$all" | jq -r '.tools[]')"
eq all-chat-eq     "$(bash "$EXTRACT" chat "$FIX")"     "$(printf '%s' "$all" | jq -r '.chat[]')"

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

echo "=== config validate (id shape: catch placeholder/truncated ids like the DSID class) ==="
# Well-formed ids (UUID data-source ids + 32-hex db ids) pass; a non-empty but MALFORMED id fails
# loudly. This is the guard whose absence let "decisions_ds_id=DSID" silently break /recall +
# decision saves while every non-empty check still passed. Isolated config dir per case.
CFGV="$(mktemp -d "${TMPDIR:-/tmp}/iroha-cfgv.XXXXXX")"
CV="$HERE/../scripts/_lib/config.sh"
IROHA_CONFIG_DIR="$CFGV" bash "$CV" set session_ds_id   "6b5fc3c8-de78-4c5f-afc6-2e1e226f9378" >/dev/null
IROHA_CONFIG_DIR="$CFGV" bash "$CV" set decisions_ds_id "34809d44-346f-4d4f-9fd6-8c9c2796e2c0" >/dev/null
IROHA_CONFIG_DIR="$CFGV" bash "$CV" set decisions_db_id "128c8c81e60d4443a82cabfd84eb243f" >/dev/null
eq config-validate-clean "0" "$(IROHA_CONFIG_DIR="$CFGV" bash "$CV" validate >/dev/null 2>&1; echo $?)"
# the exact dogfood defect: a placeholder data-source id must fail, naming the offending key.
IROHA_CONFIG_DIR="$CFGV" bash "$CV" set decisions_ds_id "DSID" >/dev/null
eq config-validate-placeholder-fail "1" "$(IROHA_CONFIG_DIR="$CFGV" bash "$CV" validate >/dev/null 2>&1; echo $?)"
has config-validate-names-bad-key "decisions_ds_id" "$(IROHA_CONFIG_DIR="$CFGV" bash "$CV" validate 2>&1)"
# a malformed (non-32-hex) database id is caught too.
IROHA_CONFIG_DIR="$CFGV" bash "$CV" set decisions_ds_id "34809d44-346f-4d4f-9fd6-8c9c2796e2c0" >/dev/null
IROHA_CONFIG_DIR="$CFGV" bash "$CV" set session_db_id "not-32-hex" >/dev/null
eq config-validate-bad-dbid-fail "1" "$(IROHA_CONFIG_DIR="$CFGV" bash "$CV" validate >/dev/null 2>&1; echo $?)"
# a malformed grouping-folder id is caught too (same 32-hex page-id class as container / db ids).
IROHA_CONFIG_DIR="$CFGV" bash "$CV" set session_db_id "c58dc1018eb54393bc67bd1a6fec6551" >/dev/null
IROHA_CONFIG_DIR="$CFGV" bash "$CV" set states_folder_id "STATES" >/dev/null
eq config-validate-bad-folder-fail "1" "$(IROHA_CONFIG_DIR="$CFGV" bash "$CV" validate >/dev/null 2>&1; echo $?)"
has config-validate-folder-named "states_folder_id" "$(IROHA_CONFIG_DIR="$CFGV" bash "$CV" validate 2>&1)"
# a fresh, un-initialized config (no ids yet) has nothing to check -> clean (a new install never false-fails).
CFGV2="$(mktemp -d "${TMPDIR:-/tmp}/iroha-cfgv2.XXXXXX")"
eq config-validate-fresh-clean "0" "$(IROHA_CONFIG_DIR="$CFGV2" bash "$CV" validate >/dev/null 2>&1; echo $?)"
rm -rf "$CFGV" "$CFGV2"

echo "=== transcript-path (deterministic locate; bounded find fallback; never globs) ==="
TPHOME=$(mktemp -d "${TMPDIR:-/tmp}/iroha-tp.XXXXXX")
TPROOT="/Users/demo/Projects/app"
TPHASH=$(printf '%s' "$TPROOT" | sed 's#/#-#g')   # cwd -> project dir name (each "/" -> "-")
mkdir -p "$TPHOME/.claude/projects/$TPHASH" "$TPHOME/.claude/projects/-other-proj"
: >"$TPHOME/.claude/projects/$TPHASH/sidA.jsonl"
: >"$TPHOME/.claude/projects/-other-proj/sidB.jsonl"
# deterministic hit: the path is derived from the cwd hash, with no glob over every project dir.
eq tp-deterministic "$TPHOME/.claude/projects/$TPHASH/sidA.jsonl" "$(HOME="$TPHOME" iroha_transcript_path "$TPROOT" sidA)"
# fallback: the cwd hash misses (project root moved since launch) -> a bounded find locates it by id.
eq tp-find-fallback "$TPHOME/.claude/projects/-other-proj/sidB.jsonl" "$(HOME="$TPHOME" iroha_transcript_path "/moved/since/launch" sidB)"
# miss: an unknown session id returns empty (the caller stops and tells the user, never guesses).
eq tp-miss "" "$(HOME="$TPHOME" iroha_transcript_path "$TPROOT" nosuchsid)"
rm -rf "$TPHOME"

echo "=== session-start hook (state injection + save reminder) ==="
HOOKHOME=$(mktemp -d "${TMPDIR:-/tmp}/iroha-home.XXXXXX")
HOOKDATA=$(mktemp -d "${TMPDIR:-/tmp}/iroha-data.XXXXXX")
PROJ=$(mktemp -d "${TMPDIR:-/tmp}/iroha-proj.XXXXXX")   # repo root; State mirror at $PROJ/.iroha/state.md
HASH=$(printf '%s' "$PROJ" | sed 's#/#-#g')
mkdir -p "$HOOKHOME/.claude/projects/$HASH" "$PROJ/.iroha"
# old.jsonl: a SUBSTANTIVE unsaved session (1 file edited) -> must be surfaced in the save backlog.
printf '%s\n' \
  '{"type":"user","timestamp":"2026-06-20T10:00:00.000Z","isSidechain":false,"message":{"role":"user","content":"Fix the parser bug"}}' \
  '{"type":"assistant","timestamp":"2026-06-20T10:01:00.000Z","isSidechain":false,"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"src/parser.ts"}}]}}' \
  >"$HOOKHOME/.claude/projects/$HASH/old.jsonl"
# trivial.jsonl: a quick Q&A with no edits / little tool use -> must NOT be surfaced (signal, not noise).
printf '%s\n' \
  '{"type":"user","timestamp":"2026-06-21T09:00:00.000Z","isSidechain":false,"message":{"role":"user","content":"TRIVIAL-QA what is the time"}}' \
  '{"type":"assistant","timestamp":"2026-06-21T09:00:30.000Z","isSidechain":false,"message":{"role":"assistant","content":[{"type":"text","text":"It is morning."}]}}' \
  >"$HOOKHOME/.claude/projects/$HASH/trivial.jsonl"
printf 'STATE-CONTENT-XYZ' >"$PROJ/.iroha/state.md"
run_hook() {
  printf '{"cwd":"%s","session_id":"cur"}' "$PROJ" |
    CLAUDE_PLUGIN_ROOT="$HERE/.." IROHA_CONFIG_DIR="$HOOKDATA" HOME="$HOOKHOME" \
      bash "$HERE/../hooks/session-start.sh"
}
out=$(run_hook)
has hook-injects-state "STATE-CONTENT-XYZ" "$out"
has hook-backlog-surfaces "Fix the parser bug" "$out"      # the substantive unsaved session is listed
has hook-backlog-actionable "save-session" "$out"          # and the reminder is actionable
hasnt hook-backlog-skips-trivial "TRIVIAL-QA" "$out"       # the trivial Q&A session is NOT listed (signal, not noise)
has hook-open-count "Open items carried over" "$out"
has hook-json-shape "hookSpecificOutput" "$out"
mkdir -p "$HOOKDATA/saved" && : >"$HOOKDATA/saved/old"
hasnt hook-no-remind-when-saved "not saved to Notion" "$(run_hook)"
# compaction restart (source=compact) re-injects THIS session's conversation from its transcript
printf '{"type":"user","isSidechain":false,"message":{"role":"user","content":"COMPACT-RECAP-PROMPT please"}}\n' >"$HOOKHOME/.claude/projects/$HASH/cur.jsonl"
cout=$(printf '{"cwd":"%s","session_id":"cur","source":"compact"}' "$PROJ" |
  CLAUDE_PLUGIN_ROOT="$HERE/.." IROHA_CONFIG_DIR="$HOOKDATA" HOME="$HOOKHOME" \
    bash "$HERE/../hooks/session-start.sh")
has hook-compact-recap "re-injected after compaction" "$cout"
has hook-compact-prompt "COMPACT-RECAP-PROMPT" "$cout"
rm -f "$HOOKHOME/.claude/projects/$HASH/cur.jsonl"
rm -f "$PROJ/.iroha/state.md" "$HOOKHOME/.claude/projects/$HASH/old.jsonl" \
  "$HOOKHOME/.claude/projects/$HASH/trivial.jsonl"
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
# supersede LINEAGE: the 10th upsert arg records the predecessor id; index.sh chain walks the chain
# newest->oldest. This is the offline primitive /iroha:history follows to show "v3 <- v2 <- v1".
iroha_index_upsert "$IDXROOT" decision chA "topicX" Superseded 2026-06-24 "topicX: v1" demo "first" ""
iroha_index_upsert "$IDXROOT" decision chB "topicX" Superseded 2026-06-25 "topicX: v2" demo "second" "chA"
iroha_index_upsert "$IDXROOT" decision chC "topicX" Active 2026-06-26 "topicX: v3" demo "third" "chB"
eq index-supersedes-stored "chB" "$(iroha_index_find_topic "$IDXROOT" "topicX" | jq -r 'select(.id=="chC")|.supersedes')"
eq index-chain-walk "chC,chB,chA" "$(iroha_index_chain "$IDXROOT" chC | jq -r '.id' | paste -sd',' -)"
eq index-chain-single "chA" "$(iroha_index_chain "$IDXROOT" chA | jq -r '.id' | paste -sd',' -)"
eq index-original-no-supersedes "null" "$(iroha_index_find_topic "$IDXROOT" "topicX" | jq -r 'select(.id=="chA")|.supersedes // "null"')"
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

# rerank gate (OPT-IN cross-encoder precision filter) — armed via rerank_enabled. The contract
# paths (empty/bad input, missing model) and the graceful fallback are deterministic WITHOUT the
# ~570MB model: rerank.mjs exits 3 when the runtime/model is absent, and the hook must then degrade
# to the pure-bash BM25 advisory result (no regression). The precision win itself is measured in
# tests/rerank-eval.sh, which runs only where the model is installed.
echo "=== rerank gate (opt-in precision filter: contract + graceful fallback to BM25) ==="
IROHA_CONFIG_DIR="$RIDATA" bash "$HERE/../scripts/_lib/config.sh" set rerank_enabled true >/dev/null
RERANK="$HERE/../scripts/rerank.mjs"
if command -v node >/dev/null 2>&1; then
  # contract: empty docs -> abstain ([], exit 0) BEFORE any model load.
  eq rerank-empty-docs-abstain "[]" "$(printf '{"query":"x","docs":[]}' | node "$RERANK" 2>/dev/null)"
  # contract: malformed stdin -> exit 2.
  printf 'not-json' | node "$RERANK" >/dev/null 2>&1
  eq rerank-bad-json-exit2 "2" "$?"
  # contract: valid input but no model/runtime -> exit 3 (the caller's fallback signal).
  printf '{"query":"x","docs":[{"id":"a","text":"b"}]}' | IROHA_MODEL_DIR="$(mktemp -d)" node "$RERANK" >/dev/null 2>&1
  eq rerank-no-model-exit3 "3" "$?"
  # hook fallback: rerank armed but model absent -> MUST still inject the BM25 advisory hit.
  RREMPTY=$(mktemp -d)
  has rerank-armed-falls-back-to-bm25 "連結: relation でなく URL" \
    "$(ri "relationプロパティで連結すべきか検討したい" sidRR1 IROHA_MODEL_DIR="$RREMPTY")"
  rm -rf "$RREMPTY"
else
  echo "  SKIP  rerank gate (node not available)"
fi

# embed gate (OPT-IN dense bi-encoder) — the candidate GENERATOR for hybrid recall (the semantic
# near-matches BM25 misses). Like the reranker, the contract paths are deterministic WITHOUT the
# model: embed.mjs exits 3 when the runtime/model is absent, so the heavy tier degrades to BM25-only
# candidates. The dense RECOVERY itself is measured in tests/hybrid-eval.sh (runs only with models).
echo "=== embed gate (opt-in dense retrieval: contract + graceful fallback) ==="
EMBED="$HERE/../scripts/embed.mjs"
if command -v node >/dev/null 2>&1; then
  eq embed-empty-docs-abstain "[]" "$(printf '{"query":"x","docs":[]}' | node "$EMBED" 2>/dev/null)"
  printf 'not-json' | node "$EMBED" >/dev/null 2>&1
  eq embed-bad-json-exit2 "2" "$?"
  printf '{"query":"x","docs":[{"id":"a","text":"b"}]}' | IROHA_MODEL_DIR="$(mktemp -d)" node "$EMBED" >/dev/null 2>&1
  eq embed-no-model-exit3 "3" "$?"
else
  echo "  SKIP  embed gate (node not available)"
fi

# recall.sh — the single local-recall code path shared by the hook and tests/hybrid-eval.sh. FREE
# tier (heavy off) returns the pure BM25 advisory hits. HEAVY tier armed but models absent degrades
# to the SAME BM25 hits (embed/rerank exit 3): never a crash, and never empty when BM25 has a hit —
# the promote-not-veto invariant that fixed the silent recall regression of the old veto path.
echo "=== recall.sh (free tier BM25; heavy-armed-no-model keeps BM25 hits, never drops one) ==="
RCFREE=$(env IROHA_CONFIG_DIR="$RIDATA3" \
  bash "$HERE/../scripts/_lib/recall.sh" "$RIPROJ" "relationプロパティで連結すべきか" 3 2>/dev/null)
has recall-free-tier-bm25 "連結: relation でなく URL" "$RCFREE"
if command -v node >/dev/null 2>&1; then
  RCEMPTY=$(mktemp -d)
  RCHEAVY=$(env IROHA_CONFIG_DIR="$RIDATA3" IROHA_RECALL_FORCE_HEAVY=1 IROHA_MODEL_DIR="$RCEMPTY" \
    bash "$HERE/../scripts/_lib/recall.sh" "$RIPROJ" "relationプロパティで連結すべきか" 3 2>/dev/null)
  has recall-heavy-no-model-keeps-bm25 "連結: relation でなく URL" "$RCHEAVY"
  rm -rf "$RCEMPTY"
fi

# check-inject hook (PreToolUse write-time decision advisory). Same cheap-local recall as the prompt
# hook, but triggered by a `git commit` Bash call and querying the commit subject + staged paths. Run
# free-tier (IROHA_RERANK_DISABLE=1) for determinism without the opt-in models. RIDATA has
# recall_enabled=true (set earlier); RIPROJ holds the one-row 連結 index.
echo "=== check-inject hook (write-time decision advisory: gate, consent, abstain, inject) ==="
ci() {  # ci <commit-command> <sid> [EXTRA_ENV=val ...]
  local c="$1" s="$2"
  shift 2
  printf '{"tool_name":"Bash","tool_input":{"command":%s},"session_id":"%s","cwd":"%s"}' \
    "$(printf '%s' "$c" | jq -Rs .)" "$s" "$RIPROJ" |
    env CLAUDE_PLUGIN_ROOT="$HERE/.." IROHA_CONFIG_DIR="$RIDATA" TMPDIR="$RICACHE" \
      IROHA_RERANK_DISABLE=1 "$@" bash "$HERE/../hooks/check-inject.sh"
}
cp=$(ci 'git commit -m "relationで連結する設計を変更"' cci1)
has ci-inject-content "連結: relation でなく URL" "$cp"               # the governing Active decision
has ci-inject-shape "hookSpecificOutput" "$cp"
eq ci-gate-non-commit "" "$(ci 'git status' cci2)"                    # only `git commit` fires
eq ci-gate-disable "" "$(ci 'git commit -m "relationで連結"' cci3 IROHA_CHECK_DISABLE=1)"
eq ci-cache-second-empty "" "$(ci 'git commit -m "relationで連結する設計を変更"' cci1)"  # one note per subject/session
eq ci-abstain "" "$(ci 'git commit -m "deploy the kubernetes cluster to aws"' cci4)"  # no governing decision
# consent gate: recall_enabled not set (RIDATA3) -> no advisory.
eq ci-gate-consent "" "$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"relationで連結\""},"session_id":"cci5","cwd":"%s"}' "$RIPROJ" |
  env CLAUDE_PLUGIN_ROOT="$HERE/.." IROHA_CONFIG_DIR="$RIDATA3" TMPDIR="$RICACHE" IROHA_RERANK_DISABLE=1 \
    bash "$HERE/../hooks/check-inject.sh")"

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
# A fresh / reset repo has no mirror yet (it regenerates on the first /iroha:save-session), which
# is not a failure — like integrity.sh treating a missing index as a clean fresh project — so only
# assert when the mirror is present.
if [ -f "$HERE/../.iroha/state.md" ]; then
  realmirror=$(iroha_state_lint "$HERE/../.iroha/state.md" >/dev/null 2>&1; echo $?)
else
  realmirror=0   # no mirror yet (fresh / reset repo) — regenerates on first save
fi
eq state-lint-real-mirror "0" "$realmirror"
rm -rf "$SLDIR"

echo "=== link-lint (Notion auto-linkify guard: bare file/path tokens outside backticks/fences/links) ==="
LL="$HERE/../scripts/_lib/link-lint.sh"
# a bare filename in body text is flagged (Notion would auto-linkify it to http://…).
eq link-lint-bare-fail "1" "$(printf 'save が extract.sh を呼ぶ\n' | bash "$LL" >/dev/null 2>&1; echo $?)"
has link-lint-names-token "extract.sh" "$(printf 'save が extract.sh を呼ぶ\n' | bash "$LL" 2>&1)"
# wrapped in backticks -> clean. (SC2016: the literal backticks are test data, no expansion wanted.)
# shellcheck disable=SC2016
eq link-lint-backtick-clean "0" "$(printf 'save が `extract.sh` を呼ぶ\n' | bash "$LL" >/dev/null 2>&1; echo $?)"
# inside a fenced code block -> clean (code is not linkified).
# shellcheck disable=SC2016
eq link-lint-fence-clean "0" "$(printf '```\nextract.sh all\n```\nplain\n' | bash "$LL" >/dev/null 2>&1; echo $?)"
# an explicit [text](url) link -> clean (intentional link, not an accidental one).
eq link-lint-link-clean "0" "$(printf '[State](https://app.notion.com/p/abc123)\n' | bash "$LL" >/dev/null 2>&1; echo $?)"
# prose with periods (versions / scores) is NOT a false positive.
eq link-lint-prose-clean "0" "$(printf 'v0.2.0 をリリース。総合70/100。Node20警告。\n' | bash "$LL" >/dev/null 2>&1; echo $?)"

echo "=== integrity (deterministic substrate self-monitoring: malformed/dup-id/dup-active/State-link) ==="
# shellcheck disable=SC1091 # dynamic source path; the file exists at runtime
. "$HERE/../scripts/_lib/integrity.sh"
INTROOT=$(mktemp -d "${TMPDIR:-/tmp}/iroha-int.XXXXXX")
mkdir -p "$INTROOT/.iroha"
# clean baseline: two distinct-topic Active decisions + a session State links to -> clean (exit 0).
{
  printf '%s\n' '{"type":"decision","id":"d1","topic":"連結","status":"Active","date":"2026-06-24","title":"連結: URL"}'
  printf '%s\n' '{"type":"decision","id":"d2","topic":"runtime","status":"Active","date":"2026-06-24","title":"runtime: bash"}'
  printf '%s\n' '{"type":"session","id":"38a822c6-938a-811e-b58a-d62cc504920a","topic":"","status":"Complete","date":"2026-06-25","title":"2026-06-25 — x"}'
} >"$INTROOT/.iroha/index.ndjson"
printf '%s\n' '**Latest (2026-06-25):** x.' '## Recent sessions' \
  '- [2026-06-25 — x](https://www.notion.so/38a822c6938a811eb58ad62cc504920a)' \
  '## Unfinished / Next' '- [ ] y' '## Decisions' '- [Decisions DB](https://www.notion.so/128c8c81e60d4443a82cabfd84eb243f)' \
  >"$INTROOT/.iroha/state.md"
eq integrity-clean "0" "$(iroha_integrity "$INTROOT" >/dev/null 2>&1; echo $?)"
# the Decisions-DB link in "## Decisions" must NOT be mistaken for a dangling session link.
hasnt integrity-ignores-decisions-link "128c8c81" "$(iroha_integrity "$INTROOT" 2>&1)"
# duplicate Active topic (the rot that most degrades recall) -> flagged.
printf '%s\n' '{"type":"decision","id":"d3","topic":"連結","status":"Active","date":"2026-06-25","title":"連結: dup"}' \
  >>"$INTROOT/.iroha/index.ndjson"
eq integrity-dup-active-fail "1" "$(iroha_integrity "$INTROOT" >/dev/null 2>&1; echo $?)"
has integrity-dup-active-msg "duplicate Active" "$(iroha_integrity "$INTROOT" 2>&1)"
# a superseded row on the same topic is history, NOT a duplicate-Active conflict (keep the
# session row State links to, so only the superseded-vs-active rule is under test here).
{
  printf '%s\n' '{"type":"decision","id":"d1","topic":"連結","status":"Active","date":"2026-06-24","title":"連結: URL"}'
  printf '%s\n' '{"type":"decision","id":"d0","topic":"連結","status":"Superseded","date":"2026-06-20","title":"連結: 旧"}'
  printf '%s\n' '{"type":"session","id":"38a822c6-938a-811e-b58a-d62cc504920a","topic":"","status":"Complete","date":"2026-06-25","title":"2026-06-25 — x"}'
} >"$INTROOT/.iroha/index.ndjson"
eq integrity-superseded-ok "0" "$(iroha_integrity "$INTROOT" >/dev/null 2>&1; echo $?)"
# valid supersede lineage: the Active row's `supersedes` points to a predecessor that exists -> clean.
{
  printf '%s\n' '{"type":"decision","id":"d0","topic":"連結","status":"Superseded","date":"2026-06-20","title":"連結: 旧"}'
  printf '%s\n' '{"type":"decision","id":"d1","topic":"連結","status":"Active","date":"2026-06-24","title":"連結: URL","supersedes":"d0"}'
  printf '%s\n' '{"type":"session","id":"38a822c6-938a-811e-b58a-d62cc504920a","topic":"","status":"Complete","date":"2026-06-25","title":"2026-06-25 — x"}'
} >"$INTROOT/.iroha/index.ndjson"
eq integrity-lineage-ok "0" "$(iroha_integrity "$INTROOT" >/dev/null 2>&1; echo $?)"
# dangling supersedes: points to an id missing from the index -> flagged (broken /iroha:history chain).
printf '%s\n' '{"type":"decision","id":"d9","topic":"x","status":"Active","date":"2026-06-25","title":"x","supersedes":"ghost"}' \
  >>"$INTROOT/.iroha/index.ndjson"
has integrity-dangling-supersedes "broken lineage" "$(iroha_integrity "$INTROOT" 2>&1)"
# duplicate id (upsert failed to replace) -> flagged.
printf '%s\n' '{"type":"decision","id":"d1","topic":"other","status":"Active","date":"2026-06-25","title":"other"}' \
  >>"$INTROOT/.iroha/index.ndjson"
has integrity-dup-id "duplicate index id" "$(iroha_integrity "$INTROOT" 2>&1)"
# malformed index line -> flagged (we WANT this loud, unlike the tolerant extract path).
printf '%s\n' '{"type":"decision","id":"d1","topic":"x","status":"Active","date":"2026-06-24","title":"x"}' >"$INTROOT/.iroha/index.ndjson"
printf '{"type":"decision"\n' >>"$INTROOT/.iroha/index.ndjson"
has integrity-malformed "malformed index line" "$(iroha_integrity "$INTROOT" 2>&1)"
# dangling State->session link (State ahead of saved sessions: the memory-hole class) -> flagged.
printf '%s\n' '{"type":"session","id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","topic":"","status":"Complete","date":"2026-06-25","title":"a"}' >"$INTROOT/.iroha/index.ndjson"
printf '%s\n' '**Latest:** x.' '## Recent sessions' '- [y](https://www.notion.so/ffffffffffffffffffffffffffffffff)' '## Decisions' '- [DB](u)' >"$INTROOT/.iroha/state.md"
has integrity-dangling-state "State ahead of saved sessions" "$(iroha_integrity "$INTROOT" 2>&1)"
rm -rf "$INTROOT"
# the project's REAL committed substrate must be clean (continuous self-monitoring in CI: a drifted
# index or a State-ahead-of-sessions hole can never reach green).
eq integrity-real-substrate "0" "$(iroha_integrity "$HERE/.." >/dev/null 2>&1; echo $?)"

echo "=== result: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
