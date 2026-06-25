**Latest (2026-06-25):** 忖度なし評価(76/100)で rot 3件(State 破損・Projects 陳腐化・MRR 過大記載)を実証し、機能追加でなくトラスト根治を選択。save-session を単一ソース化して State 破損を根治、project のバッククォート徹底、300行スケールを実証(recency は YAGNI 据置)、audit に破損検出を追加、extract の You-anchor 漏れを修正。selftest 70→72・recall-eval 100%・scale 8/8 全 green・5 commits。

## Recent sessions
- [2026-06-25 — トラスト根治とスケール実証](https://app.notion.com/p/38a822c6938a8189b9e6f5c84d304efa)
- [2026-06-25 — ローカルBM25リコール再設計](https://app.notion.com/p/38a822c6938a816092e3fb101f391cdb)
- [2026-06-25 — 90点ロードマップ実装と検証](https://app.notion.com/p/38a822c6938a813a9968ef7b2375b86b)
- [2026-06-25 — 徹底評価とドッグフーディング再開](https://app.notion.com/p/38a822c6938a812c92e2e40b02e39b13)
- [2026-06-24 — Notion 連携の設計と Phase 1 実装](https://app.notion.com/p/389822c6938a81b8832ae4aa55d62121)

## Unfinished / Next
- [ ] 旧 Session ページ群の体裁リトロフィット（低優先・再保存で自動反映）

見送り中（正本は Decisions DB）: SessionEnd 自動保存 / importance 学習 / reflection 層 — いずれも YAGNI 据置で、必要性が実測で出たら再評価。数百セッション規模の recall スケール検証は本セッションで完了。

## Decisions
過去の判断・理由・却下案は [Decisions DB](https://app.notion.com/p/128c8c81e60d4443a82cabfd84eb243f) を参照。実装前に `/iroha:recall <topic>` で確認（UserPromptSubmit フックがローカル BM25 で関連決定を常時先出し）。
