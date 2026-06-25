#!/usr/bin/env bash
# iroha-for-notion — deterministic transcript extraction.
# Reads a Claude Code session JSONL (~/.claude/projects/<hash>/<id>.jsonl) and emits
# noise-free, deterministic views for /iroha:save-session. Read-only.
# stdout = the requested view only; diagnostics go to stderr.
#
# Usage: extract.sh <files|commands|meta|prompts|stats|tools|chat> <transcript.jsonl>
#
#   files     unique files touched via Edit/Write/MultiEdit/NotebookEdit
#   commands  unique Bash commands (first line of each)
#   meta      JSON {title, started, ended, cwd, gitBranch, model, sessionId}
#   prompts   the human's actual messages, in order — the You-side anchor for chat
#             highlights. Tool results, sidechains, and system-injected wrappers
#             (<task-notification> / <command-*> / <system-reminder>) are excluded, so
#             save-session never has to invent a "You" line from memory.
#   stats     JSON {userTurns, assistantTurns, toolCalls, filesEdited, bashCommands,
#             durationMin, startedAt, endedAt} — the numbers for a metrics dashboard.
#   tools     per-tool usage tally, most-used first (e.g. "- `Bash` ×12").
#   chat      the full cleaned chat (human turns + assistant text only; thinking /
#             tool_use / tool_result / sidechains / system wrappers stripped) — the
#             audit trail behind the curated highlights.
#
# Transcripts can be truncated (a crash / interrupt leaves an unfinished last line),
# so each line is parsed independently with `fromjson?` — malformed lines are skipped,
# never fatal. The whole extraction does not fail just because one record is broken.
set -u

cmd="${1:-}"
file="${2:-}"

if [ -z "$cmd" ] || [ -z "$file" ]; then
  echo "usage: extract.sh <files|commands|meta|prompts|stats|tools|chat> <transcript.jsonl>" >&2
  exit 2
fi
if [ ! -f "$file" ]; then
  echo "extract.sh: no such file: $file" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || {
  echo "extract.sh: jq is required" >&2
  exit 1
}

# Parse each line independently (tolerant of truncated / malformed records); the views
# below then slurp the valid objects into the array they operate on.
records() { jq -R 'fromjson? // empty' "$file"; }

case "$cmd" in
  files)
    records | jq -rs '
      [ .[] | select(.isSidechain != true) | select(.type == "assistant")
        | .message.content[]? | select(.type == "tool_use")
        | select(.name | test("^(Edit|Write|MultiEdit|NotebookEdit)$"))
        | { verb: (if .name == "Write" then "write" else "edit" end),
            path: (.input.file_path // .input.notebook_path // empty) }
        | select(.path != null)
      ] | unique_by(.path) | .[] | "- `" + .path + "` (" + .verb + ")"
    '
    ;;
  commands)
    records | jq -rs '
      [ .[] | select(.isSidechain != true) | select(.type == "assistant")
        | .message.content[]? | select(.type == "tool_use") | select(.name == "Bash")
        | (.input.command // empty) | select(. != null) | split("\n")[0]
      ] | unique | .[] | "- `" + . + "`"
    '
    ;;
  prompts)
    records | jq -rs '
      [ .[] | select(.isSidechain != true) | select(.type == "user")
        | select(.message.content | type == "string") | .message.content
        | select(test("^\\s*<(command-message|command-name|task-notification|system-reminder|local-command-stdout|bash-input|bash-stdout|user-prompt-submit-hook)") | not)
        | gsub("\\s+"; " ") | gsub("^ +| +$"; "")
        | select(. != "") | .[0:200]
      ] | .[] | "- " + .
    '
    ;;
  meta)
    records | jq -rs '
      (map(select(.timestamp)) | sort_by(.timestamp)) as $ts
      | {
          title: ((map(select(.type == "ai-title")) | last | .aiTitle) //
                  ((map(select(.type == "user" and (.message.content | type == "string"))) | first | .message.content) // "Untitled session")),
          started: ($ts | first | .timestamp),
          ended: ($ts | last | .timestamp),
          cwd: (map(select(.cwd)) | last | .cwd),
          gitBranch: ([ .[] | .gitBranch // empty ] | last),
          model: ([ .[] | select(.type == "assistant") | .message.model // empty ] | last),
          sessionId: ([ .[] | .sessionId // empty ] | last)
        }
    '
    ;;
  stats)
    records | jq -s '
      def realuser: select(.isSidechain != true) | select(.type == "user")
        | select(.message.content | type == "string")
        | select(.message.content | test("^\\s*<(command-message|command-name|task-notification|system-reminder|local-command-stdout|bash-input|bash-stdout|user-prompt-submit-hook)") | not);
      def asof: .timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
      (map(select(.timestamp)) | sort_by(.timestamp)) as $t
      | {
          userTurns:      ([ .[] | realuser ] | length),
          assistantTurns: ([ .[] | select(.isSidechain != true) | select(.type == "assistant") | select(any(.message.content[]?; .type == "text")) ] | length),
          toolCalls:      ([ .[] | select(.isSidechain != true) | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") ] | length),
          filesEdited:    ([ .[] | select(.isSidechain != true) | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | select(.name | test("^(Edit|Write|MultiEdit|NotebookEdit)$")) | (.input.file_path // .input.notebook_path // empty) ] | unique | length),
          bashCommands:   ([ .[] | select(.isSidechain != true) | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | select(.name == "Bash") ] | length),
          startedAt:      ($t | first | .timestamp),
          endedAt:        ($t | last | .timestamp),
          durationMin:    (if ($t | length) > 1 then ((($t | last | asof) - ($t | first | asof)) / 60 | floor) else 0 end)
        }
    '
    ;;
  tools)
    records | jq -rs '
      [ .[] | select(.isSidechain != true) | select(.type == "assistant")
        | .message.content[]? | select(.type == "tool_use") | .name ]
      | group_by(.) | map({name: .[0], n: length}) | sort_by(-.n)
      | .[] | "- `" + .name + "` ×" + (.n | tostring)
    '
    ;;
  chat)
    records | jq -rs '
      [ .[] | select(.isSidechain != true)
        | if (.type == "user" and (.message.content | type == "string")
              and (.message.content | test("^\\s*<(command-message|command-name|task-notification|system-reminder|local-command-stdout|bash-input|bash-stdout|user-prompt-submit-hook)") | not))
          then { role: "You", text: .message.content }
          elif (.type == "assistant")
          then (.message.content[]? | select(.type == "text") | { role: "Claude", text: .text })
          else empty end
        | (.text | gsub("\\s+"; " ") | gsub("^ +| +$"; "")) as $t
        | select($t != "")
        | ($t | if length > 600 then .[0:600] + " …(略)" else . end) as $c
        | "**" + .role + "** " + $c
      ] | .[]
    '
    ;;
  *)
    echo "extract.sh: unknown command: $cmd" >&2
    exit 2
    ;;
esac
