**Latest (2026-06-29):** iroha 自身の Bun+TypeScript / Claude 開発ドキュメント遵守度を公式情報で照合しながら点検し、見つかった磨き込みを mumei で実装（3 レビュー全合格）。続けて v0.4.2 をパッチリリースし（main 反映・CI/release 緑・dependabot が SHA bump PR を即提示）、save 後に残課題を GitHub issue #4–#8 へ整理した。

## Recent sessions
- [2026-06-29 — 監査と Bun+TS ハードニング](https://app.notion.com/p/38d822c6938a815dacf7d70999439257)
- [2026-06-28 — save 本文の決定論レンダリング](https://app.notion.com/p/38d822c6938a8168ad5be2856b9a70dc)
- [2026-06-27 — HEAVY recall を Bun in-process 化](https://app.notion.com/p/38c822c6938a8163a391fdddc69a683a)

## Unfinished / Next
- [ ] 残課題は GitHub issue で追跡: typed index 化 (#4) / CI クロスプラットフォーム (#5) / 合成 secret fixture 移設 (#6) / 第2プロジェクトで save ドッグフード=N=1 脱出 (#7) / State 注入の positioning (#8)

## Decisions
過去の判断・理由・却下案は [Decisions DB（Active ビュー）](https://app.notion.com/p/7544d1820fc247028948855c08becce2) を参照（リコール / 決定記録 / ポジショニング / HEAVY実行 / 依存方針 / 保存 / GitHub / CI の 8 件が Active）。技術スタックは未登録 — `/iroha:project` で Projects 行を作成すると相互リンクされる。
