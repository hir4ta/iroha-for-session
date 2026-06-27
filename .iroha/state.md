**Latest (2026-06-27):** pure bash から Bun/TypeScript へ全面移行して v0.3.0 をリリース、検索ライブラリは自前 BM25 + `transformers.js` 維持を確定、Notion を完全クリアしてまっさらから init を再実行し、Session 本文を保存前に検証する `session-lint` を追加。

## Recent sessions
- [2026-06-27 — Bun/TS 移行と session-lint](https://app.notion.com/p/38c822c6938a810c8e25c6bdddce8792)

## Unfinished / Next
- [ ] N=1 脱出: 非 iroha / 非日本語の実プロジェクトで iroha 全体を実証（総合の天井を上げる唯一の手）
- [ ] GitHub 拡張 Phase 0（N=1 脱出後）: `gh` 境界付き PR 抽出 + golden eval・Session↔PR の URL 連結
- [ ] フルチャット子ページの巨大セッション対策（コンテキスト枯渇リスク）

## Decisions
過去の判断・理由・却下案は [Decisions DB（Active ビュー）](https://app.notion.com/p/db9931c0b38644ee99cebd50518a9a39) を参照。技術スタックは未登録 — `/iroha:project` で Projects 行を作成すると相互リンクされる。
