**Latest (2026-06-27):** pure bash から Bun/TypeScript へ全面移行して v0.3.0 をリリース、検索ライブラリは自前 BM25 + `transformers.js` 維持を確定、Notion を完全クリアしてまっさらから init を再実行、Session 本文を保存前に検証する `session-lint` を追加、SKILL の jq/grep データ処理を `index.ts` 型付きサブコマンド化、改善ライブラリを調査済み（次は導入）。

## Recent sessions
- [2026-06-27 — Bun/TS 移行と session-lint](https://app.notion.com/p/38c822c6938a810c8e25c6bdddce8792)

## Unfinished / Next
- [ ] **ライブラリ導入（次の着手・リサーチ済み）**: ① `fast-check`（devDep・配布契約を変えない）で `extract.ts` パース / `link-lint.ts` 不変条件の property test ② `Zod v4`（**初のプロダクション依存＝「依存ゼロ」契約を変える決定・要合意**）で `config.ts`/`index.ts`/`integrity.ts`/Notion property map を検証 ③ `transformers` v4 TRIAL（`bun run embed.ts` 直実行→通れば node-subprocess 撤廃・`.mjs` を `.ts` 化）。HOLD（再調査不要）: 検索 lib は自前維持、remark / ArkType / Valibot / date-fns / Temporal は今は入れない。
- [ ] **N=1 脱出**（最優先）: 非 iroha / 非日本語の実プロジェクトで iroha 全体を実証（総合の天井を上げる唯一の手）。
- [ ] **GitHub 拡張 Phase 0**（N=1 脱出後）: `gh` 境界付き PR 抽出 + golden eval・Session↔PR の URL 連結。
- [ ] 巨大セッションのフルチャット逐語投稿の機械化（手写しはドリフトするので `extract.ts` の chat 出力を Notion へ機械投稿する小ツール）。

## Decisions
過去の判断・理由・却下案は [Decisions DB（Active ビュー）](https://app.notion.com/p/db9931c0b38644ee99cebd50518a9a39) を参照。技術スタックは未登録 — `/iroha:project` で Projects 行を作成すると相互リンクされる。
