#!/usr/bin/env bash
# state-lint.sh — validate a State body BEFORE it is published to Notion / committed.
#
# Under save-session §8's single-source rule, the repo mirror <root>/.iroha/state.md is written
# ONCE and the byte-identical text is published to the Notion State page — so linting the mirror
# also validates what Notion will render. This catches the State-corruption class found while
# dogfooding (a save left the Notion State as a summary-only callout with literal \n / \t escapes
# leaking in), turning the most defect-prone write surface from "detect after the fact (audit)"
# into "prevent before write": run it in save-session before publishing, in audit as the
# deterministic escape/section check, and in selftest against the real committed mirror so a
# corrupt State can never reach CI green. Pure bash + the file; no network.
#
# Checks are LANGUAGE-INDEPENDENT (structure only — no dependence on translated heading text, so
# it never false-positives on a State written in another conversation language):
#   1. non-empty file.
#   2. no literal "\n" / "\t" two-character escape sequences — the body must contain REAL
#      newlines/tabs; the escaped form is exactly the leak that degraded a past State.
#   3. >= 3 "## " section headings — a State that degraded to a summary-only callout loses the
#      Recent-sessions / Unfinished / Decisions sections it exists to provide.
#   4. a summary line before the first "## " heading (the "**Latest (...)**" one-liner).
#
# Usage: state-lint.sh <state.md>   (exit 0 = clean; exit 1 = issues printed, one per line)
set -u

# iroha_state_lint <file>  -> 0 clean / 1 issues (each printed on its own line).
iroha_state_lint() {
  local f="$1" issues=0 headings
  if [ ! -s "$f" ]; then
    echo "state-lint: missing or empty file: $f"
    return 1
  fi
  if grep -qF '\n' "$f" || grep -qF '\t' "$f"; then
    printf '%s\n' 'state-lint: literal \n or \t escape sequence found — State must contain real newlines/tabs'
    issues=1
  fi
  headings=$(grep -cE '^## ' "$f")
  if [ "$headings" -lt 3 ]; then
    echo "state-lint: only $headings '## ' sections (need >= 3: Recent sessions / Unfinished / Decisions) — State may have degraded to a summary"
    issues=1
  fi
  if ! awk '/^## /{exit} /[^[:space:]]/{found=1} END{exit (found?0:1)}' "$f"; then
    echo "state-lint: no summary line before the first '## ' heading"
    issues=1
  fi
  [ "$issues" -eq 0 ]
}

# CLI: usable from skills as `bash state-lint.sh <state.md>`. Guarded so sourcing is a no-op.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  iroha_state_lint "${1:-}"
fi
