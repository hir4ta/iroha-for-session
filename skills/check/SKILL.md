---
name: check
description: Check the current working changes against this project's past Active decisions and flag conflicts — "this diff looks like it contradicts the decision we made (and why)". Bridges git reality (uncommitted changes + recent commits) with the Decisions DB so you catch a silent course-reversal before you commit or open a PR. Read-only. Triggers on "/iroha:check", "does this change violate a past decision?", "check my changes against decisions", and naturally before committing/pushing a non-trivial change.
argument-hint: ""
---

# iroha: check

Catch the case the rest of iroha can't: you are **about to ship code that quietly
contradicts a decision the project already made** — without remembering it. recall answers
"did we decide X?" when *you* ask; audit checks the memory's *own* health; check points the
memory **at your current diff** and asks "does this work conflict with an Active decision?".
It is the git-reality → Decisions bridge (the sibling `iroha-for-agents` injects git truth at
edit-time; here we reconcile that truth against the *why* in Notion). **Read-only** — it
reports, never writes. Report in the **user's conversation language**.

## 1. Preconditions

```bash
L="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh"; IDX="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/index.sh"
bash "$L" get decisions_ds_id    # empty -> tell the user to run /iroha:init, then stop
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "NOT_A_GIT_REPO"; }  # stop if not
```

If `decisions_ds_id` is empty, tell the user to run `/iroha:init` and stop. If `NOT_A_GIT_REPO`,
say there is nothing to check against git and stop.

## 2. Gather git reality (deterministic)

```bash
ROOT="$PWD"
git rev-parse --abbrev-ref HEAD                 # current branch
git diff --stat HEAD                            # shape of the uncommitted change (tracked)
git diff HEAD --name-only                       # changed tracked paths (the strongest topic signal)
git ls-files --others --exclude-standard        # NEW untracked files (a new file is a change too —
                                                # it will NOT show in `git diff`, so list it here)
git log --oneline -10                           # recent commit subjects (work just landed)
```

The **uncommitted changes** are the primary subject (tracked edits *and* new untracked files —
what you are about to commit); the recent commits are secondary context (what this branch just
did). For a new file, read it directly (it has no `git diff`). If diff, untracked, and the recent
commits are all empty, say the tree is clean and there is nothing to check — stop.

## 3. Enumerate the Active decisions, then narrow to candidates

The local index lists **every** decision (free-plan `notion-search` cannot enumerate). Take the
`Active` ones — those are the live constraints a change can violate:

```bash
bash "$IDX" list "$ROOT" decision | jq -c 'select(.status=="Active")'   # id/topic/title/snippet
```

The Active set is small, so you can scan all of it against the diff. To **narrow to the most
likely conflicts** on a larger project, run the local BM25 search over salient terms pulled from
the changed paths / diff (file names, new dependencies, identifiers, removed approaches):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/search.sh" "$ROOT" "<salient terms from the diff>" decision 5
```

## 4. Judge each candidate (the intelligence)

For every Active decision that plausibly touches the change, decide whether the diff
**contradicts** it. A real conflict is the change doing the thing the decision rejected, or
removing/altering what the decision mandated — e.g. a decision `Link: URL not relation` vs a diff
that adds a `relation` property; `Notion: MCP only` vs a diff that introduces an API-token client.
Confirm before you flag it — `notion-fetch` the decision id for the full `Rationale` /
`Alternatives` so you compare against the real reason, not just the title:

```bash
# notion-fetch <decision-page-id>   # read Rationale + Alternatives to confirm the contradiction
```

Be strict about what counts (avoid false alarms): a change that is merely *near* a decision's
topic is **not** a conflict; flag only a genuine contradiction. Distinguish three outcomes per
decision: **conflict** (the diff opposes an Active decision), **intentional supersede** (the diff
deliberately changes a past decision — legitimate, but the memory must be updated), or **no
conflict**.

## 5. Report (honest, abstain when clean)

Lead with conflicts, most load-bearing first (Lost-in-the-Middle). For each:
- **what** in the diff conflicts, and with **which decision** (link the Notion page);
- **why** it matters — quote the decision's `Rationale` (the reason it was made);
- the **suggested action**: revert/adjust the change to honour the decision, OR — if the reversal
  is *intentional* — keep it and **record the course-change** by running `/iroha:save-session`
  (which supersedes the old decision, never overwrites: a change of mind is itself memory). Do
  **not** write to Notion from here.

If nothing conflicts, **say so plainly** — "no Active decision conflicts with the current
changes" is a real, valuable result. Never invent a conflict to look thorough (AbstentionBench:
a confident false flag is worse than an honest all-clear), and never claim a decision exists that
the index/Notion does not show.

## Notes

- **Read-only and advisory.** check never mutates Notion or the repo; it surfaces conflicts for
  *you* to act on. The actual supersede happens in `/iroha:save-session`.
- **Scope.** It reasons over Active decisions for this `Project`; superseded decisions are history
  and are not constraints. Enumeration is complete via the index, so "no conflict" is trustworthy
  (not just a search top-N miss).
- Good moments to run it: before a commit on a non-trivial change, before opening a PR, or when
  picking up a branch you (or a teammate) left mid-way.
