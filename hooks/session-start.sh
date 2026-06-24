#!/usr/bin/env bash
# iroha-for-notion — SessionStart hook. Injects the project's last saved State
# (from a local mirror; this hook cannot reach Notion) plus a gentle reminder when
# the previous session was never saved. Silent (exit 0, no stdout) when there is
# nothing to say. stdout is reserved for the hook JSON; logs go to stderr.
set -u

input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ -z "$cwd" ] && exit 0

# shellcheck disable=SC1091 # dynamic source; resolved at runtime via CLAUDE_PLUGIN_ROOT
. "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh"

ctx=""

# 1. Continuity: the project's last saved State (local mirror from /save-session).
state_md="$(iroha_state_md_path "$cwd")"
if [ -s "$state_md" ]; then
  ctx="iroha — このプロジェクトの前回状態:
$(cat "$state_md")
"
fi

# 2. Save reminder: is the most recent prior transcript unsaved?
projdir="$HOME/.claude/projects/$(printf '%s' "$cwd" | sed 's#/#-#g')"
last=""
for f in "$projdir"/*.jsonl; do
  [ -e "$f" ] || continue
  case "$f" in */"${sid}.jsonl") continue ;; esac
  if [ -z "$last" ] || [ "$f" -nt "$last" ]; then last="$f"; fi
done
if [ -n "$last" ] && [ ! -e "$(iroha_saved_dir)/$(basename "$last" .jsonl)" ]; then
  ctx="${ctx}
(前回のセッションは iroha に未保存です。必要なら /iroha-for-notion:save-session で保存できます。)"
fi

[ -z "$ctx" ] && exit 0
esc=$(printf '%s' "$ctx" | jq -Rs .)
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$esc"
