**Latest (2026-06-27):** opt-in の高精度リコールを Bun 内実行へ変え node/npm 撤廃、`fast-check`(開発用) 導入、`Zod` は配布が複雑化するため見送り依存ゼロ維持、巨大セッションの Full chat を `chat-chunks.ts` で決定論分割、英語 recall を回帰テスト化して N=1 脱出の準備を完了。別プロジェクト(mumei)で実走し、起動バグ(`rerank:setup` の cwd 依存)を修正。実走で「save が機械作業を Claude に負わせすぎて重い・壊れやすい（特に全チャットの逐語投稿が手作業依存）」という構造的フィードバックを取得＝次回の最優先改善。

## Recent sessions
- [2026-06-27 — HEAVY recall を Bun in-process 化](https://app.notion.com/p/38c822c6938a8163a391fdddc69a683a)

## Unfinished / Next
- [ ] **save の機械化（最優先・次回着手）**: N=1 実走フィードバックで判明。Full chat の逐語投稿が LLM 手写し依存（"never fabricate" を最も揺るがす）・ID 配線の multi-round・保存1回の手数の重さ。机械化は「MCP 一本・トークン無し」の核心と緊張する（Notion 直書きは API トークンを要する）ので、方向（トークン導入の是非）を次回まず議論。`session-lint` の改行エスケープ誤検知（code span 非除外）は単独修正可能。
- [ ] N=1 脱出（実走開始・継続）: mumei で init/save を実走しフィードバック取得済み。残課題は上記 save 机械化。
- [ ] GitHub 拡張 Phase 0（N=1 脱出後）: `gh` 境界付き PR 抽出 + Session↔PR の URL 連結
- [ ] `rerank-eval` の `TRUEQ` は現コーパス3決定依存 — 決定が増えたら再ラベル/拡張

## Decisions
過去の判断・理由・却下案は [Decisions DB（Active ビュー）](https://app.notion.com/p/7544d1820fc247028948855c08becce2) を参照。技術スタックは未登録 — `/iroha:project` で Projects 行を作成すると相互リンクされる。
