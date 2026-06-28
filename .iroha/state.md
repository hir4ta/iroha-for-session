**Latest (2026-06-29):** iroha 自身の Bun+TypeScript / Claude 開発ドキュメント遵守度を公式情報で照合しながら点検し、見つかった磨き込み（CI の安全な版固定、依存・設定の整理、テストの堅牢化、スキル設定の明示、長い手順書の分割）を mumei で 8 コミット実装して専用ブランチ audit-fixes に反映した。設計・正しさの欠陥は無く、3 つの自動レビューはすべて合格。

## Recent sessions
- [2026-06-29 — 監査と Bun+TS ハードニング](https://app.notion.com/p/38d822c6938a815dacf7d70999439257)
- [2026-06-28 — save 本文の決定論レンダリング](https://app.notion.com/p/38d822c6938a8168ad5be2856b9a70dc)
- [2026-06-27 — HEAVY recall を Bun in-process 化](https://app.notion.com/p/38c822c6938a8163a391fdddc69a683a)

## Unfinished / Next
- [ ] N=1 脱出: 別の実プロジェクトで save フロー（compose-session / PR 連結）を実走しフィードバック取得 [carried 4x — 今回は iroha 自身に mumei を適用したが第2の実プロジェクトでの save 実走は未達]
- [ ] `state.md` の SessionStart 注入をネイティブ記憶に寄せて削るか（positioning 判断・保留）
- [ ] audit-fixes ブランチの PR 化（今回は見送り。必要時 `gh pr create -B main -H audit-fixes`）
- [ ] (任意) `tests/lib.test.ts` の合成 secret fixture を `tests/fixtures/` へ移し mumei secret-scan の再フラグを回避

## Decisions
過去の判断・理由・却下案は [Decisions DB（Active ビュー）](https://app.notion.com/p/7544d1820fc247028948855c08becce2) を参照（リコール / 決定記録 / ポジショニング / HEAVY実行 / 依存方針 / 保存 / GitHub / CI の 8 件が Active）。技術スタックは未登録 — `/iroha:project` で Projects 行を作成すると相互リンクされる。
