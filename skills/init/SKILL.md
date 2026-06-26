---
name: init
description: One-time setup for iroha-for-notion. Creates the Sessions and Decisions databases in the user's Notion via the connected Notion MCP, then records their ids locally. Run before the first /save-session, or to reconnect / join a teammate's existing iroha workspace. Triggers on "/iroha:init", "set up iroha", "initialize notion memory".
argument-hint: "[notion-parent-page-url]"
---

# iroha: init

Set up (or join) the Notion workspace iroha writes sessions to. Idempotent:
pointing it at a page that already has `Sessions` / `Decisions` / `Projects` databases
reuses them instead of creating duplicates. All ids are cached in
`$HOME/.iroha-for-notion/config.json` (non-secret; override the dir with
`IROHA_CONFIG_DIR`). Auth is the user's **Notion MCP** OAuth connection — there is no
API token.

## Steps

1. **Check Notion MCP is connected.** Confirm tools like `notion-create-database`,
   `notion-create-pages`, `notion-fetch` are available. If not, ask the user to
   connect the hosted Notion MCP (OAuth) and stop.

2. **Check existing config:**

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh" get session_ds_id
   ```

   If it prints an id, iroha is already initialized — say so and stop unless the
   user explicitly asks to re-initialize.

3. **Resolve the parent page.** Use `$ARGUMENTS` as a Notion page URL/ID if given;
   else ask the user for the page URL where iroha should live. `notion-fetch` it to
   confirm access and get the bare page id (32-hex).

4. **Reuse if present (team-join).** If the fetched page already contains `Sessions`,
   `Decisions`, and `Projects` databases, capture their data source ids (step 7) and
   stop — this is how a teammate joins a shared workspace without creating duplicates.

5. **Create the three databases** directly under that page with `notion-create-database`,
   which takes **SQL DDL** (`CREATE TABLE`). Do NOT use `RELATION` columns (the MCP
   relation write path is buggy); link records with a `URL` column instead. Replace
   `iroha-for-notion` in the `Project` option with the current project name
   (basename of the user's cwd). Notion auto-creates select options on write, so the
   seeded options are just starting values.

   **Localize to the user's conversation language.** The DDL below is the canonical
   **English template**. When you actually issue it, translate the human-facing **`Type`**
   option labels into the user's conversation language (e.g. for a Japanese user, use the
   Japanese terms for Research / Design / Implementation / etc.). Keep everything
   **structural in English** so the schema is stable across languages and locales: all
   property *names*, the `Status` and `Languages` option values, and the `Project` value
   (the repo name). save-session then writes `Type` in that same language. (This mirrors
   the working convention: structural keys English, content categories in the user's
   language.)

   Sessions:

   ```
   parent: {"type":"page_id","page_id":"<PAGE_ID>"}   title: "Sessions"
   schema: CREATE TABLE ("Name" TITLE, "Date" DATE, "Project" SELECT('iroha-for-notion':blue), "Branch" RICH_TEXT, "Author" RICH_TEXT, "Summary" RICH_TEXT, "Status" SELECT('Complete':green, 'WIP':yellow, 'Interrupted':red), "Type" MULTI_SELECT('Research':blue, 'Requirements':purple, 'Design':orange, 'Implementation':green, 'Fix':red, 'Refactor':brown, 'Review':gray))
   ```

   Decisions:

   ```
   parent: {"type":"page_id","page_id":"<PAGE_ID>"}   title: "Decisions"
   schema: CREATE TABLE ("Name" TITLE, "Project" SELECT('iroha-for-notion':blue), "Status" SELECT('Active':green, 'Superseded':gray), "Tags" MULTI_SELECT('architecture':blue, 'dependency':orange, 'process':gray), "Rationale" RICH_TEXT, "Alternatives" RICH_TEXT, "Session" URL, "Date" DATE)
   ```

   Projects (one row per project — the cross-project architecture layer for catch-up
   and "how do our other <language> projects do this?"):

   ```
   parent: {"type":"page_id","page_id":"<PAGE_ID>"}   title: "Projects"
   schema: CREATE TABLE ("Name" TITLE, "Languages" MULTI_SELECT('TypeScript':blue, 'JavaScript':yellow, 'Go':blue, 'Python':green, 'Rust':orange, 'Bash':gray), "Frameworks" RICH_TEXT, "DevTools" RICH_TEXT, "CI" RICH_TEXT, "Repo" URL, "Updated" DATE)
   ```
   Only `Languages` is multi_select (finite, filterable); Frameworks / DevTools / CI are
   rich_text (libraries are too many / too varied for select — let `notion-search` find
   them in the text).

6. **Read the data source ids from each result.** `notion-create-database` returns a
   `<data-source url="collection://<DS_ID>">` tag. Rows are created under the **data
   source id** (collection), NOT the database id — capture both.

7. **Save the ids:**

   ```bash
   L="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh"
   bash "$L" set container_page_id "<PAGE_ID>"
   bash "$L" set session_db_id   "<SESSIONS_DATABASE_ID>"
   bash "$L" set session_ds_id   "<SESSIONS_DATA_SOURCE_ID>"
   bash "$L" set decisions_db_id "<DECISIONS_DATABASE_ID>"
   bash "$L" set decisions_ds_id "<DECISIONS_DATA_SOURCE_ID>"
   bash "$L" set projects_db_id  "<PROJECTS_DATABASE_ID>"
   bash "$L" set projects_ds_id  "<PROJECTS_DATA_SOURCE_ID>"
   bash "$L" set recall_enabled  true   # arm enforced JIT recall (the UserPromptSubmit hook
                                        # stays idle until this is true — so a fresh install
                                        # that never ran init costs nothing per prompt)
   ```

8. **Create views for fast team browsing.** On the **Sessions** database (uses its
   `database_id` + data source id from step 6):
   - `notion-create-view` type `table` named **`Recent`**, `SORT BY "Date" DESC` — make
     this the primary entry ("what did we do recently?" is the most common need, and a
     date-descending table beats Calendar/Board for it).
   - `notion-create-view` type `calendar`, `CALENDAR BY "Date"` (visual, secondary).
   - `notion-create-view` type `board`, `GROUP BY "Status" SORT BY "Date" ASC` (secondary).
   On the **Decisions** database:
   - `notion-create-view` type `table` named **`Active`**, `FILTER "Status" = 'Active'`
     so superseded / reverted decisions do not clutter "what did we decide?".
   On the **Projects** database:
   - `notion-create-view` type `board` named **`By Language`**, `GROUP BY "Languages"
     SORT BY "Updated" DESC` so a teammate can browse "all our Go / Python projects".

9. **Add an entry-point guide to the parent page.** `notion-update-page`
   `insert_content` at `{"type":"start"}` a one-line `<callout color="gray_bg">`: how to
   navigate (progress → State / past decisions → Decisions / each run → Sessions
   `Recent`) and the naming conventions — sessions `YYYY-MM-DD — <topic>`, decisions
   `<topic>: <choice>`. This hands a teammate the whole map in one glance. Write the guide
   text in the user's conversation language (the English here is the canonical template; the
   prose a teammate reads should be localized).

10. **Confirm** with links to both databases and tell the user they can now run
    `/iroha:save-session`. Mention that **enforced just-in-time recall is now on**: each
    substantive prompt triggers a bounded background recall of relevant past decisions
    (disable any time with `IROHA_RECALL_DISABLE=1`; verify readiness with
    `bash "${CLAUDE_PLUGIN_ROOT}/hooks/recall-inject.sh" --selfcheck`).

    **Optional higher-precision recall (opt-in, heavy).** Proactive recall runs on the pure-bash
    BM25 stage by default — zero deps, instant. For higher precision (a local cross-encoder reranker
    that filters out same-vocabulary-but-off-topic decisions BM25 cannot separate), the user can run
    `npm run rerank:setup` once: it installs a Node runtime dep and downloads a local model
    (~570MB for the default multilingual model, or set
    `IROHA_RERANK_MODEL=hotchpotch/japanese-reranker-xsmall-v2` for ~37MB). Mention this as an option,
    do **not** run it as part of init — a fresh install must stay dependency-free.

## Notes

- Databases are shared across projects; the `Project` property separates them.
- Teams: one person runs init, shares the page in Notion, teammates run init against
  the same page to join (step 4 reuses the existing databases).
