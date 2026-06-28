#!/bin/sh
# Test stub for `gh`: ignores its args and prints a fixed `gh pr list --json ...` payload, so gh.ts's
# prsForBranch() can be exercised end-to-end (spawn -> parse -> sort) with no real gh / network.
# Pointed at via IROHA_GH_BIN in tests. Includes a MERGED + an OPEN pr to assert OPEN-first ordering.
cat <<'JSON'
[{"number":3,"url":"https://github.com/o/r/pull/3","title":"chore: old","state":"MERGED"},{"number":7,"url":"https://github.com/o/r/pull/7","title":"feat: shiny","state":"OPEN"}]
JSON
