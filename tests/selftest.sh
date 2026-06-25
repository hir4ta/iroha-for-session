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

echo "=== recall-inject hook (enforced JIT recall: guards, gate, cache, degrade, inject) ==="
RIDATA=$(mktemp -d "${TMPDIR:-/tmp}/iroha-ri-data.XXXXXX")
RIBIN=$(mktemp -d "${TMPDIR:-/tmp}/iroha-ri-bin.XXXXXX")
RICACHE=$(mktemp -d "${TMPDIR:-/tmp}/iroha-ri-cache.XXXXXX")
IROHA_CONFIG_DIR="$RIDATA" bash "$HERE/../scripts/_lib/config.sh" set decisions_ds_id "DSID" >/dev/null
IROHA_CONFIG_DIR="$RIDATA" bash "$HERE/../scripts/_lib/config.sh" set session_ds_id "SSID" >/dev/null
IROHA_CONFIG_DIR="$RIDATA" bash "$HERE/../scripts/_lib/config.sh" set recall_enabled true >/dev/null
# stub `timeout` (macOS lacks it): drop the duration arg, exec the rest
printf '#!/usr/bin/env bash\nshift\nexec "$@"\n' >"$RIBIN/timeout"
# stub `claude`: return a canned recall hit
printf '#!/usr/bin/env bash\necho "- DecisionX: chose Y — because Z — 2026-06-25 — https://notion.example/x"\n' >"$RIBIN/claude"
chmod +x "$RIBIN/timeout" "$RIBIN/claude"
ri() {  # ri <prompt> <sid> [EXTRA_ENV=val ...]
  local p="$1" s="$2"
  shift 2
  printf '{"prompt":"%s","session_id":"%s","cwd":"/x"}' "$p" "$s" |
    env CLAUDE_PLUGIN_ROOT="$HERE/.." IROHA_CONFIG_DIR="$RIDATA" TMPDIR="$RICACHE" \
      PATH="$RIBIN:$PATH" "$@" bash "$HERE/../hooks/recall-inject.sh"
}
hp=$(ri "please add a login endpoint with validation" sid1)
has ri-inject-shape "hookSpecificOutput" "$hp"
has ri-inject-content "DecisionX" "$hp"
eq ri-cache-second-empty "" "$(ri "please add a login endpoint with validation" sid1)"
eq ri-gate-short "" "$(ri "hi there" sid2)"
eq ri-gate-slash "" "$(ri "/iroha:recall some topic here" sid3)"
eq ri-recursion-guard "" "$(ri "build a substantial new feature now" sidR IROHA_RECALL_CHILD=1)"
eq ri-disable "" "$(ri "build a substantial new feature now" sidD IROHA_RECALL_DISABLE=1)"
# abstention: stub returns NONE -> no injection
printf '#!/usr/bin/env bash\necho NONE\n' >"$RIBIN/claude"
chmod +x "$RIBIN/claude"
eq ri-abstain-empty "" "$(ri "a distinct substantive request to recall" sid4)"
# not initialized: empty config -> degrade (no injection)
RIDATA2=$(mktemp -d "${TMPDIR:-/tmp}/iroha-ri-data2.XXXXXX")
eq ri-not-initialized "" "$(printf '{"prompt":"another substantive request here","session_id":"sid5","cwd":"/x"}' |
  env CLAUDE_PLUGIN_ROOT="$HERE/.." IROHA_CONFIG_DIR="$RIDATA2" TMPDIR="$RICACHE" PATH="$RIBIN:$PATH" \
    bash "$HERE/../hooks/recall-inject.sh")"
# config gate: initialized but recall_enabled not set -> no injection (distribution-safe default)
RIDATA3=$(mktemp -d "${TMPDIR:-/tmp}/iroha-ri-data3.XXXXXX")
IROHA_CONFIG_DIR="$RIDATA3" bash "$HERE/../scripts/_lib/config.sh" set decisions_ds_id "DSID" >/dev/null
IROHA_CONFIG_DIR="$RIDATA3" bash "$HERE/../scripts/_lib/config.sh" set session_ds_id "SSID" >/dev/null
eq ri-gate-recall-disabled "" "$(printf '{"prompt":"a substantive request with recall off","session_id":"sid6","cwd":"/x"}' |
  env CLAUDE_PLUGIN_ROOT="$HERE/.." IROHA_CONFIG_DIR="$RIDATA3" TMPDIR="$RICACHE" PATH="$RIBIN:$PATH" \
    bash "$HERE/../hooks/recall-inject.sh")"
# selfcheck (offline): all prerequisites stubbed/present -> READY, exit 0, guard asserted
sc=$(env CLAUDE_PLUGIN_ROOT="$HERE/.." IROHA_CONFIG_DIR="$RIDATA" PATH="$RIBIN:$PATH" \
  bash "$HERE/../hooks/recall-inject.sh" --selfcheck)
has ri-selfcheck-ready "READY" "$sc"
has ri-selfcheck-guard "recursion guard short-circuits" "$sc"
# selfcheck must work when run by hand (no CLAUDE_PLUGIN_ROOT) by deriving root from $0
sc2=$(env -u CLAUDE_PLUGIN_ROOT IROHA_CONFIG_DIR="$RIDATA" PATH="$RIBIN:$PATH" \
  bash "$HERE/../hooks/recall-inject.sh" --selfcheck)
has ri-selfcheck-derives-root "READY" "$sc2"
rm -rf "$RIDATA" "$RIDATA2" "$RIDATA3" "$RIBIN" "$RICACHE"

echo "=== result: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
