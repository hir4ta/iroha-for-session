---
name: save-session
description: Save the current Claude Code session to Notion as structured, visual, queryable memory — decisions (with rationale and rejected alternatives), dev rules, work-state (done / unfinished), changed files, key commands, and the full human<->Claude chat log. Use at the end of a working session, or when the user says "save this session" / "セッションを保存" / "まとめて保存". Requires a connected Notion MCP and a prior /iroha-for-notion:init.
argument-hint: "[Complete|WIP|Interrupted]"
---

# iroha-for-notion: save-session

Persist this session to Notion so humans and future Claude sessions can recall what
was decided, what is unfinished, and why. You produce the intelligence (summary,
decisions, rules, classification); `scripts/extract.sh` produces the deterministic
parts (chat log, files, commands, metadata). All Notion writes go through the
connected Notion MCP. Write Notion content in the **user's conversation language**.

## 1. Preconditions

Confirm Notion MCP is connected, then load the cached ids:

```bash
L="${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh"
bash "$L" get session_ds_id    # empty -> tell the user to run /iroha-for-notion:init, then stop
bash "$L" get decisions_ds_id
bash "$L" get container_page_id
```

## 2. Locate this session's transcript

```bash
TX=$(ls -t "$HOME/.claude/projects/"*"/${CLAUDE_SESSION_ID}.jsonl" 2>/dev/null | head -1)
echo "$TX"
```

## 3. Deterministic extraction

```bash
E="${CLAUDE_PLUGIN_ROOT}/scripts/extract.sh"
bash "$E" meta     "$TX"   # JSON: title, started, ended, cwd, gitBranch, model
bash "$E" files    "$TX"
bash "$E" commands "$TX"
git config user.name 2>/dev/null || echo "unknown"   # Author
```

(The chat log is fetched in step 7, not here — it is large.)

## 4. Compose the content (from your memory of the session + the extracted data)

- **Summary** — 1-3 sentences (the `Summary` property + search snippet).
- **Decisions** — each: the decision, *why*, and *rejected alternatives*. A decision
  to NOT do something counts.
- **Rules** — dev rules/conventions established this session (CLAUDE.md / memory
  promotion candidates).
- **Done** / **Unfinished / Next** — work-state, for the Project State carry-over.
- **Failures** — error -> root cause -> fix.
- **Type** — any of 調査 / 要件定義 / 設計 / 実装 / 修正 / リファクタ / レビュー
  (infer from the transcript).
- **Status** — `$ARGUMENTS` if given, else infer Complete / WIP / Interrupted.

## 5. Create the Session row

`notion-create-pages` with `parent: {"type":"data_source_id","data_source_id":"<session_ds_id>"}`.
Property map uses SQLite values:
- `Name` (title), `Project`, `Status`, `Branch`, `Author`, `Summary` — plain strings.
- `Type` — a JSON array **string**, e.g. `"[\"設計\", \"実装\"]"`.
- Date — expanded keys: `"date:Date:start"` = started ISO, `"date:Date:is_datetime"` = 1.

**`content` = Notion-flavored Markdown, visual and monochrome (no emoji icons).** Read
the spec once via the MCP resource `notion://docs/enhanced-markdown-spec`. Use:
- a header `<callout color="blue_bg">` with the one-line summary;
- a meta `<table header-column="true">` (Project / Status / Type / Date / Branch · Author);
- `## アーキテクチャ` with a ```mermaid``` diagram when the work has structure;
- `## 決定事項` as a `<table header-row="true">` with a `<tr color="blue_bg">` header
  (columns: 決定 / なぜ / 却下した代替案);
- `## 開発ルール` as a `<callout color="gray_bg">`;
- `## 進捗` as a green_bg callout (Done) + an orange_bg callout (Unfinished, `- [ ]`);
- `## 詳細` with `<details><summary>…</summary>` toggles for files and commands.
Wrap file names / commands in backticks so Notion does not auto-linkify them. Indent
callout / toggle / table children with **tabs**. Keep the returned page URL.

Set a clean monochrome page icon:
`icon: "https://www.notion.so/icons/notebook_gray.svg"`.

## 6. Create the Decision rows

For each decision, `notion-create-pages` under `decisions_ds_id`: `Name` = the
decision, `Project`, `Status` = `Active`, `Tags` (JSON array string), `Rationale`,
`Alternatives`, `Session` = the Session page URL from step 5, `"date:Date:start"`.

## 7. Append the full chat log (visual, in batches)

The chat is the whole point — never summarize it here. Render it as alternating
Notion callouts (You = blue_bg, Claude = gray_bg) deterministically:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/extract.sh" chat-callouts "$TX" > "$TMP/chat.md"
wc -c "$TMP/chat.md"
```

First append a `## 会話ログ` heading to the Session page (`notion-update-page`,
`insert_content`, `position {"type":"end"}`). Then append the chat **in batches** at
whole-callout boundaries (one MCP call cannot hold a large chat): repeatedly read the
next chunk of `chat.md` (e.g. a few dozen callouts) and `insert_content` it with
`position {"type":"end"}` until the file is consumed. If the chat is very large, tell
the user how many batches you appended.

## 8. Update the Project State page (continuity core)

```bash
PROJ="$PWD"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/_lib/config.sh" get-state "$PROJ"
```

State body (monochrome): latest summary + date, active decisions (brief), active
rules, and the carried-over **Unfinished / Next** list.
- If get-state is empty: `notion-create-pages` under `container_page_id`
  (title `State — <project>`, icon `https://www.notion.so/icons/target_gray.svg`),
  then `bash …/config.sh set-state "$PROJ" "<page_id>"`.
- Else: `notion-update-page` `replace_content` on that page id.

## 9. Mark saved + report

```bash
mkdir -p "${CLAUDE_PLUGIN_DATA}/saved" && : > "${CLAUDE_PLUGIN_DATA}/saved/${CLAUDE_SESSION_ID}"
```

Report the Session page URL, how many decisions were recorded, how many chat batches
were appended, and that the Project State was updated.

## Notes

- Do not write secrets to Notion; if the transcript surfaced any, omit them.
- `extract.sh chat` already drops noise (tool results, thinking, sidechains,
  task-notifications, local-command output) — it is the genuine human<->Claude chat.
