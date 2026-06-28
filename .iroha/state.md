**Latest (2026-06-28):** v0.4.0 をリリース（①新しいプロジェクトでは記憶が十分たまるまで自動の関連表示を控える、②決めた瞬間に 1 行だけ記録する軽量 `/iroha:decide`、③Claude Code 標準メモリとの住み分けを明確化）。続けて **Session↔PR の URL 連結**を実装 — `gh` で現在ブランチの PR を境界付き・fail-soft に取得し、Session 行の `PR` プロパティと本文リンクに反映（PR が無い／`gh` が無い場合は無害に省略）。ドッグフードで過去決定の記録漏れ 1 件と決定履歴の id 比較バグ 1 件を発見・修正。

## Recent sessions
- [2026-06-28 — save 本文の決定論レンダリング](https://app.notion.com/p/38d822c6938a8168ad5be2856b9a70dc)
- [2026-06-27 — HEAVY recall を Bun in-process 化](https://app.notion.com/p/38c822c6938a8163a391fdddc69a683a)

## Unfinished / Next
- [ ] N=1 脱出: 別プロジェクト mumei で compose 化した新 save フローと PR 連結を実走しフィードバック取得 [carried 3x]
- [ ] `state.md` の SessionStart 注入をネイティブ記憶に寄せて削るかは保留（positioning 判断・「ポジショニング」決定の Alternative ③）
- [ ] State 本文・決定 body（supersede lineage 行）の決定論レンダリングは後回し（YAGNI・小さく既存 lint 済み）

## Decisions
過去の判断・理由・却下案は [Decisions DB（Active ビュー）](https://app.notion.com/p/7544d1820fc247028948855c08becce2) を参照（リコール / 決定記録 / ポジショニング / HEAVY実行 / 依存方針 / 保存 の 6 件が Active）。技術スタックは未登録 — `/iroha:project` で Projects 行を作成すると相互リンクされる。
