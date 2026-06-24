---
name: init
description: One-time setup for iroha-for-notion. Creates the Sessions and Decisions databases in the user's Notion via the connected Notion MCP, then records their ids locally. Run before the first /save-session, or to reconnect / join a teammate's existing iroha workspace. Triggers on "/iroha-for-notion:init", "set up iroha", "initialize notion memory".
argument-hint: "[notion-parent-page-url]"
---

# iroha-for-notion: init

Set up (or join) the Notion workspace iroha writes sessions to. Idempotent:
pointing it at a page that already has `Sessions` / `Decisions` databases reuses
them instead of creating duplicates. All ids are cached in
`${CLAUDE_PLUGIN_DATA}/config.json` (non-secret). Auth is the user's **Notion MCP**
OAuth connection — there is no API token.

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

4. **Reuse if present (team-join).** If the fetched page already contains `Sessions`
   and `Decisions` databases, capture their data source ids (step 7) and stop — this
   is how a teammate joins a shared workspace without creating duplicates.

5. **Create the two databases** directly under that page with `notion-create-database`,
   which takes **SQL DDL** (`CREATE TABLE`). Do NOT use `RELATION` columns (the MCP
   relation write path is buggy); link records with a `URL` column instead. Replace
   `iroha-for-notion` in the `Project` option with the current project name
   (basename of the user's cwd). Notion auto-creates select options on write, so the
   seeded options are just starting values.

   Sessions:

   ```
   parent: {"type":"page_id","page_id":"<PAGE_ID>"}   title: "Sessions"
   schema: CREATE TABLE ("Name" TITLE, "Date" DATE, "Project" SELECT('iroha-for-notion':blue), "Branch" RICH_TEXT, "Author" RICH_TEXT, "Summary" RICH_TEXT, "Status" SELECT('Complete':green, 'WIP':yellow, 'Interrupted':red), "Type" MULTI_SELECT('調査':blue, '要件定義':purple, '設計':orange, '実装':green, '修正':red, 'リファクタ':brown, 'レビュー':gray))
   ```

   Decisions:

   ```
   parent: {"type":"page_id","page_id":"<PAGE_ID>"}   title: "Decisions"
   schema: CREATE TABLE ("Name" TITLE, "Project" SELECT('iroha-for-notion':blue), "Status" SELECT('Active':green, 'Superseded':gray, 'Reverted':red), "Tags" MULTI_SELECT('architecture':blue, 'dependency':orange, 'process':gray), "Rationale" RICH_TEXT, "Alternatives" RICH_TEXT, "Session" URL, "Date" DATE)
   ```

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
   ```

8. **Confirm** with links to both databases and tell the user they can now run
   `/iroha-for-notion:save-session`.

## Notes

- Databases are shared across projects; the `Project` property separates them.
- Teams: one person runs init, shares the page in Notion, teammates run init against
  the same page to join (step 4 reuses the existing databases).
