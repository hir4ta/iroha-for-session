#!/usr/bin/env bash
# iroha-for-notion — deterministic transcript extraction.
# Reads a Claude Code session JSONL (~/.claude/projects/<hash>/<id>.jsonl) and emits
# human-readable, noise-free views. Read-only. stdout = the requested view only.
#
# Usage: extract.sh <chat|files|commands|meta|title> <transcript.jsonl>
#
#   chat      cleaned conversation: human turns + assistant text only
#             (thinking / tool_use / tool_result / sidechain are dropped)
#   files     unique files touched via Edit/Write/MultiEdit/NotebookEdit
#   commands  unique Bash commands (first line of each)
#   title     ai-title if present, else the first human prompt
#   meta      JSON {title, started, ended, cwd, gitBranch, model, sessionId}
set -u

cmd="${1:-}"
file="${2:-}"

if [ -z "$cmd" ] || [ -z "$file" ]; then
  echo "usage: extract.sh <chat|files|commands|meta|title> <transcript.jsonl>" >&2
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

case "$cmd" in
  chat)
    jq -rs '
      [ .[]
        | select(.isSidechain != true and .isMeta != true)
        | if (.type == "user" and (.message.content | type == "string")
              and ((.message.content) | test("^(<task-notification>|<local-command|<command-name>|<command-message>|<command-args>|\\[Request interrupted|Caveat:|<system-reminder>|Another Claude session sent a message|\\[SYSTEM NOTIFICATION)") | not)) then
            "**You:** " + .message.content
          elif (.type == "assistant") then
            ( [ .message.content[]? | select(.type == "text") | .text ] | join("\n") )
            | select(length > 0) | "**Claude:** " + .
          else empty end
      ] | join("\n\n")
    ' "$file"
    ;;
  chat-callouts)
    # Same cleaned chat as `chat`, rendered as alternating Notion callouts
    # (You = blue_bg, Claude = gray_bg). For Notion-flavored Markdown page content.
    bash "$0" chat "$file" | awk '
      function flush() { if (open) { print "</callout>"; print ""; open = 0 } }
      /^\*\*You:\*\*/    { flush(); print "<callout color=\"blue_bg\">"; open = 1; line = $0; sub(/^\*\*You:\*\* /, "\t**You** ", line); print line; next }
      /^\*\*Claude:\*\*/ { flush(); print "<callout color=\"gray_bg\">"; open = 1; line = $0; sub(/^\*\*Claude:\*\* /, "\t**Claude** ", line); print line; next }
                        { if (open) print "\t" $0 }
      END { flush() }
    '
    ;;
  files)
    jq -rs '
      [ .[] | select(.isSidechain != true) | select(.type == "assistant")
        | .message.content[]? | select(.type == "tool_use")
        | select(.name | test("^(Edit|Write|MultiEdit|NotebookEdit)$"))
        | { verb: (if .name == "Write" then "write" else "edit" end),
            path: (.input.file_path // .input.notebook_path // empty) }
        | select(.path != null)
      ] | unique_by(.path) | .[] | "- `" + .path + "` (" + .verb + ")"
    ' "$file"
    ;;
  commands)
    jq -rs '
      [ .[] | select(.isSidechain != true) | select(.type == "assistant")
        | .message.content[]? | select(.type == "tool_use") | select(.name == "Bash")
        | (.input.command // empty) | select(. != null) | split("\n")[0]
      ] | unique | .[] | "- `" + . + "`"
    ' "$file"
    ;;
  title)
    jq -rs '
      (map(select(.type == "ai-title")) | last | .aiTitle) //
      ((map(select(.type == "user" and (.message.content | type == "string"))) | first | .message.content) // "Untitled session")
    ' "$file"
    ;;
  meta)
    jq -rs '
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
    ' "$file"
    ;;
  *)
    echo "extract.sh: unknown command: $cmd" >&2
    exit 2
    ;;
esac
