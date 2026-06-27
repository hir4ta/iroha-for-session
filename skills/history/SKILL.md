---
name: history
description: Walk the supersede LINEAGE of a topic — how and why a decision evolved over time, "X was superseded by Y was superseded by Z (and here is the reason at each step)". Where recall answers "what did we decide?" with the current Active choice, history shows the whole chain behind it, so a course-reversal is visible as a story, not a single flat row. Read-only. Triggers on "/iroha:history <topic>", "how did our decision on X evolve?", "why did we change our mind about X?", "show the history of the X decision".
argument-hint: "[topic or question]"
---

# iroha: history

Show the **evolution** of a decision, not just its current state. iroha never overwrites a
decision when the project changes its mind: the old row stays as `Status=Superseded` and the new
one links back to it via `Supersedes`. This skill follows that chain so you can read the *story* —
what was chosen first, what replaced it, and the reason at each turn. **Read-only**; it never
writes. Report in the **user's conversation language**.

## 1. Preconditions

```bash
L="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.ts"; IDX="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/index.ts"
SEARCH="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/search.ts"; ROOT="$PWD"
bun "$L" get decisions_ds_id    # empty -> tell the user to run /iroha:init, then stop
```

If `decisions_ds_id` is empty, tell the user to run `/iroha:init` and stop.

## 2. Resolve the topic to a chain head (the current Active decision)

The lineage is walked from the **most recent** decision on the topic (usually the Active one) back
to the original. Find that head from `$ARGUMENTS`:

```bash
# a) Exact-ish topic match (the "<topic>:" prefix is the dedup key).
bun "$IDX" find-topic "$ROOT" "$ARGUMENTS"
# b) Fuzzy fallback when the user typed a paraphrase, not the literal topic.
bun "$SEARCH" "$ROOT" "$ARGUMENTS" decision 5 0
```

Pick the head:
- Prefer a row with `status="Active"` whose `topic` (or title) matches the query.
- If several topics match, **list them and ask** which lineage to trace (do not guess).
- If nothing matches, say so honestly ("no decision recorded for <topic>") and stop — never invent
  a chain.

## 3. Walk the lineage (offline, from the local index)

```bash
bun "$IDX" chain "$ROOT" "<head-id>"   # newest first: head, predecessor, …, original
```

Each line is a decision record `{id, topic, status, date, title, supersedes, text}`. A chain of
length 1 means the decision has no predecessor — say "this decision has no earlier version" rather
than padding it.

## 4. Deepen with the canonical reason (Notion is the source of truth)

The index `text` is only a short search snippet. For the actual **Rationale** and **rejected
Alternatives** at each step, fetch the full pages (the index has no content):

```bash
# for each id in the chain (cap at ~6 to stay cheap):
#   notion-fetch <id>   -> read Name / Rationale / Alternatives / Date / Session
```

Use the Notion MCP `notion-fetch` tool with each chain id. If a fetch fails or Notion is
unreachable, fall back to the index `text` snippet and say it is a summary, not the full rationale.

## 5. Present the evolution (newest → oldest)

Render the chain as a short narrative, current decision first, each step annotated with **why it
changed** (drawn from the newer decision's Rationale — a supersede almost always states what the
predecessor got wrong):

```
Topic: リコール  (3 decisions, current is Active)

▸ NOW  リコール: hybrid(検索+index)        Active      2026-06-25
       Why: notion-search is top-N + write-lag; a keys-only local index enumerates everything …
   ↑ replaced
   リコール: notion-search 主体             Superseded  2026-06-25
       Why it was dropped: search alone misses freshly-saved rows (write-lag) …
   ↑ replaced
   リコール: ローカル grep                  Superseded  2026-06-24
       (original)  query-database-view 400s on the free plan, so local grep …
```

Keep it tight: the choice, the date, the one-line reason, and the supersede arrows. Link each
decision's Notion URL (`https://www.notion.so/<bare-id>`) so the user can open the full page.

## Notes

- **Lineage is URL-linked, not a Notion relation.** Each decision's `Supersedes` is a URL to its
  predecessor (the same pattern as the Session↔Decision link), chosen to dodge the MCP relation-
  write bug. The local index mirrors the same edge as a `supersedes` id so the walk is offline.
- **Only forward-populated chains are complete.** `save-session` links every new supersession going
  forward; older chains were backfilled only where the predecessor was stated unambiguously. If a
  Superseded decision has no `supersedes` and no successor links to it, its lineage is unknown —
  say so rather than guessing a predecessor.
- This skill is **read-only**. Repairing a missing/incorrect link is `/iroha:audit`'s job (a
  reversible edit), not history's.
