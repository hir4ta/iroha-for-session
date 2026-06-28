# テスト

- **`bun test`** が**振る舞いの正本 (behavioral oracle)**。`tests/*.test.ts` が各モジュールを
  in-process import して直接検証 (hooks のみ subprocess で stdin→stdout を検証)。`bun test` (0 = ALL PASS)。
  型は `bunx tsc --noEmit`、lint/format は `bun run lint` (biome)。
- 品質 eval は別: `bun tests/recall-eval.ts` (BM25 recall) / `recall-scale.ts` (スケール)。
  両者とも**凍結 fixture コーパス** (`tests/fixtures/recall-corpus/.iroha/index.ndjson`) に対して回す
  ので、ワークスペース再 save で決定 id が churn しても golden がドリフトしない (生きた index に
  結合させない)。fixture の再生成は意図的に行う時だけ (`cp .iroha/index.ndjson tests/fixtures/...`)。
- 抽出ロジックは `tests/fixtures/` に**実トランスクリプトと同形の JSONL**を置いて検証する。
  最低限おさえる観点:
  - `type=user` の content が文字列 (= 人間の発言) と、配列の `tool_result` (= ツール出力) の判別
  - 人間の実発言の決定論抽出 (`prompts`): 文字列 content のみ。`tool_result` / sidechain /
    システム注入ラッパー (`<task-notification>` / `<command-*>` / `<system-reminder>`) を除外
    (= 会話ハイライトの You アンカー。Claude が You 発言を創作しないための地上の真実)
  - 変更ファイル (Edit/Write tool_use)・主要コマンド (Bash tool_use) の抽出
- **Notion 書き込みは Claude が SKILL 内で MCP ツールを呼ぶため自動テスト対象外** (組み立てる
  TS 関数が無い)。決定論部分 (`extract.ts` / `config.ts` / hooks) のみ oracle で
  守る。SKILL が渡すプロパティ map のフォーマットは実機でしか出ないので **SKILL に型を明記**して
  担保する: `Type` / `Tags` / `Languages` は JSON array **文字列**、`date:…:is_datetime` は
  **数値** 0/1 (文字列 `"1"` は 400)、checkbox は `__YES__` / `__NO__`。
- Arrange → Act → Assert。テスト名は「何を検証するか」を明示。
- プロダクションコードをテストを通すためだけに変えない。根本原因を直す。
