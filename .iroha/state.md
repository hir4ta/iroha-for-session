**Latest (2026-06-27):** opt-in の高精度リコールを node 経由から Bun 内実行へ変え node/npm 撤廃、検索精度テストの既存不具合も修正。`fast-check`(開発用) で不変条件を property test、`Zod` は配布ユーザーに追加インストールを強いるため見送り**依存ゼロを維持**、`CONTRIBUTING` を Bun/TS 更新。巨大セッションの Full chat を `chat-chunks.ts` で決定論分割（手投稿のドリフト排除）、英語コーパスでの recall を回帰テスト化して **N=1 脱出の準備を完了**（非日本語でも動くことをコード検証で実証）。

## Recent sessions
- [2026-06-27 — HEAVY recall を Bun in-process 化](https://app.notion.com/p/38c822c6938a81aeade3c3ff45f0bbc0)
- [2026-06-27 — Bun/TS 移行と session-lint](https://app.notion.com/p/38c822c6938a810c8e25c6bdddce8792)

## Unfinished / Next
- [ ] N=1 脱出（最優先・準備完了）: 実走は別プロジェクトの Claude Code セッションで（plugin install → `/iroha:init` → `/iroha:save-session`）。コード検証で英語動作は確認済み [carried 2x]
- [ ] GitHub 拡張 Phase 0（N=1 脱出後）: `gh` 境界付き PR 抽出 + golden eval・Session↔PR の URL 連結 [carried 2x]
- [ ] `rerank-eval` の `TRUEQ` は現コーパス3決定依存 — 決定が増えたら再ラベル/拡張

## Decisions
過去の判断・理由・却下案は [Decisions DB（Active ビュー）](https://app.notion.com/p/db9931c0b38644ee99cebd50518a9a39) を参照。技術スタックは未登録 — `/iroha:project` で Projects 行を作成すると相互リンクされる。
