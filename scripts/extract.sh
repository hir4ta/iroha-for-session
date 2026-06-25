#!/usr/bin/env bash
# iroha-for-notion — deterministic transcript extraction.
# Reads a Claude Code session JSONL (~/.claude/projects/<hash>/<id>.jsonl) and emits
# noise-free, deterministic views for /iroha:save-session. Read-only.
# stdout = the requested view only; diagnostics go to stderr.
#
# Usage: extract.sh <files|commands|meta> <transcript.jsonl>
#
#   files     unique files touched via Edit/Write/MultiEdit/NotebookEdit
#   commands  unique Bash commands (first line of each)
#   meta      JSON {title, started, ended, cwd, gitBranch, model, sessionId}
#
# Transcripts can be truncated (a crash / interrupt leaves an unfinished last line),
# so each line is parsed independently with `fromjson?` — malformed lines are skipped,
# never fatal. The whole extraction does not fail just because one record is broken.
set -u

cmd="${1:-}"
file="${2:-}"

if [ -z "$cmd" ] || [ -z "$file" ]; then
  echo "usage: extract.sh <files|commands|meta> <transcript.jsonl>" >&2
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
  *)
    echo "extract.sh: unknown command: $cmd" >&2
    exit 2
    ;;
esac
