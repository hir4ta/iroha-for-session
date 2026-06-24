#!/usr/bin/env bash
# iroha-for-notion selftest — behavioral oracle for deterministic extraction.
# Runs scripts/extract.sh against a synthetic transcript fixture and asserts the
# cleaned views include the right content and exclude noise.
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

echo "=== extract chat (human + assistant text only) ==="
chat=$(bash "$EXTRACT" chat "$FIX")
has chat-human "Please add a login endpoint" "$chat"
has chat-assistant "Sure, I'll add it." "$chat"
has chat-final "Done, the endpoint is added." "$chat"
hasnt chat-no-thinking "SECRET THOUGHTS" "$chat"
hasnt chat-no-toolresult "FILE WRITTEN noise" "$chat"
hasnt chat-no-sidechain "SIDECHAIN" "$chat"
hasnt chat-no-notification "NOISE-TASKNOTIF" "$chat"

echo "=== extract files (deduped) ==="
files=$(bash "$EXTRACT" files "$FIX")
has files-path "src/login.ts" "$files"
eq files-dedup "1" "$(printf '%s\n' "$files" | grep -c 'src/login.ts')"

echo "=== extract commands (first line only) ==="
cmds=$(bash "$EXTRACT" commands "$FIX")
has cmd-bash "npm test" "$cmds"
hasnt cmd-firstline-only "echo done" "$cmds"

echo "=== extract title (ai-title wins) ==="
title=$(bash "$EXTRACT" title "$FIX")
eq title-aititle "Add login endpoint" "$title"

echo "=== extract chat-callouts (Notion bubbles) ==="
cc=$(bash "$EXTRACT" chat-callouts "$FIX")
has cc-callout-open "<callout color=\"blue_bg\">" "$cc"
has cc-you-label "**You**" "$cc"
has cc-claude-label "**Claude**" "$cc"
hasnt cc-no-notification "NOISE-TASKNOTIF" "$cc"

echo "=== config helper (roundtrip, isolated dir) ==="
CLAUDE_PLUGIN_DATA="$(mktemp -d "${TMPDIR:-/tmp}/iroha-cfg.XXXXXX")"
export CLAUDE_PLUGIN_DATA
# shellcheck disable=SC1091 # dynamic source path; the file exists at runtime
. "$HERE/../scripts/_lib/config.sh"
iroha_config_set session_db_id "DB123"
eq config-set-get "DB123" "$(iroha_config_get session_db_id)"
eq config-missing-empty "" "$(iroha_config_get nonexistent_key)"
iroha_config_set_state_page "/repo/foo" "PAGE9"
eq config-state-roundtrip "PAGE9" "$(iroha_config_get_state_page "/repo/foo")"
eq config-state-missing "" "$(iroha_config_get_state_page "/repo/bar")"
rm -rf "$CLAUDE_PLUGIN_DATA"

echo "=== session-start hook (state injection + save reminder) ==="
HOOKHOME=$(mktemp -d "${TMPDIR:-/tmp}/iroha-home.XXXXXX")
HOOKDATA=$(mktemp -d "${TMPDIR:-/tmp}/iroha-data.XXXXXX")
PROJ="/tmp/iroha-proj"
HASH="-tmp-iroha-proj"
mkdir -p "$HOOKHOME/.claude/projects/$HASH" "$HOOKDATA/state"
: >"$HOOKHOME/.claude/projects/$HASH/old.jsonl"
printf 'STATE-CONTENT-XYZ' >"$HOOKDATA/state/${HASH}.md"
run_hook() {
  printf '{"cwd":"%s","session_id":"cur"}' "$PROJ" |
    CLAUDE_PLUGIN_ROOT="$HERE/.." CLAUDE_PLUGIN_DATA="$HOOKDATA" HOME="$HOOKHOME" \
      bash "$HERE/../hooks/session-start.sh"
}
out=$(run_hook)
has hook-injects-state "STATE-CONTENT-XYZ" "$out"
has hook-reminds-unsaved "未保存" "$out"
has hook-json-shape "hookSpecificOutput" "$out"
mkdir -p "$HOOKDATA/saved" && : >"$HOOKDATA/saved/old"
hasnt hook-no-remind-when-saved "未保存" "$(run_hook)"
rm -f "$HOOKDATA/state/${HASH}.md" "$HOOKHOME/.claude/projects/$HASH/old.jsonl"
eq hook-silent-when-empty "" "$(run_hook)"
rm -rf "$HOOKHOME" "$HOOKDATA"

echo "=== result: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
