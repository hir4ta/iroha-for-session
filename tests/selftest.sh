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
rm -f "$PROJ/.iroha/state.md" "$HOOKHOME/.claude/projects/$HASH/old.jsonl"
eq hook-silent-when-empty "" "$(run_hook)"
# missing CLAUDE_PLUGIN_ROOT must exit 0 silently, not crash under set -u
env -u CLAUDE_PLUGIN_ROOT HOME="$HOOKHOME" bash "$HERE/../hooks/session-start.sh" <<<'{"cwd":"/x","session_id":"y"}' >/dev/null 2>&1
eq hook-no-plugin-root-exit0 "0" "$?"
rm -rf "$HOOKHOME" "$HOOKDATA" "$PROJ"

echo "=== result: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
