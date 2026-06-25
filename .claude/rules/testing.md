# テスト

- `tests/selftest.sh` が**振る舞いの正本 (behavioral oracle)**。pure bash で完結
  (bats 依存なし。iroha-for-agents 流)。`bash tests/selftest.sh; echo $?` (0 = ALL PASS)。
- 抽出ロジックは `tests/fixtures/` に**実トランスクリプトと同形の JSONL**を置いて検証する。
  最低限おさえる観点:
  - `type=user` の content が文字列 (= 人間の発言) と、配列の `tool_result` (= ツール出力) の判別
  - 整形チャット (human 発言 + assistant text のみ、thinking/tool_use/tool_result 除外)
  - 変更ファイル (Edit/Write tool_use)・主要コマンド (Bash tool_use) の抽出
- **Notion 書き込みは Claude が SKILL 内で MCP ツールを呼ぶため自動テスト対象外** (組み立てる
  bash 関数が無い)。決定論部分 (`extract.sh` / `config.sh` / `session-start.sh`) のみ oracle で
  守る。SKILL が渡すプロパティ map のフォーマットは実機でしか出ないので **SKILL に型を明記**して
  担保する: `Type` / `Tags` / `Languages` は JSON array **文字列**、`date:…:is_datetime` は
  **数値** 0/1 (文字列 `"1"` は 400)、checkbox は `__YES__` / `__NO__`。
- Arrange → Act → Assert。テスト名は「何を検証するか」を明示。
- プロダクションコードをテストを通すためだけに変えない。根本原因を直す。
