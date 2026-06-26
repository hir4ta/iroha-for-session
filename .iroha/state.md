**Latest (2026-06-26):** 三度目評価(73/100)からの連続改善を完遂・全 push・CI green: ①config妥当性の自己監視で Critical(`decisions_ds_id=DSID`)根治 ②`/iroha:audit` 相当でコンテンツ rot 一掃 ③秘密/誤字スキャンを CI に追加(標準 action は node_modules 誤走査で乖離したため `pre-commit run` 経由に変更し CI==local 化) ④cross-encoder rerank(570MB bge-m3)を deploy+実機検証(JP/EN同義語ギャップ rank1・誤注入0/5)し rerank-eval に恒久ロック ⑤session recall を実測(良好。当初「貧弱」は測定バグの誤認で撤回)し recall-eval に4 session ケース追加 ⑥rerank 品質の CI 検証を専用 workflow(手動/週次・bge-m3・cache)で実現。selftest 103・recall-eval 13/15(86%)全green。

## Recent sessions
- [2026-06-26 — config自己監視と三度目の評価](https://app.notion.com/p/38b822c6938a81a98378cb726b9c516d)
- [2026-06-26 — 精度rerank前段と完全性自己監視](https://app.notion.com/p/38b822c6938a81869424e9ceb358df3d)
- [2026-06-25 — 評価と保存バックログ実装](https://app.notion.com/p/38a822c6938a811eb58ad62cc504920a)
- [2026-06-25 — 評価とState発行前ガード](https://app.notion.com/p/38a822c6938a810b86d7f1f2f256e101)
- [2026-06-25 — トラスト根治とスケール実証](https://app.notion.com/p/38a822c6938a8189b9e6f5c84d304efa)

## Unfinished / Next
- [ ] rerank を非iroha/非日本語の実プロジェクトで実証(iroha では deploy 済・N=1 脱出が残課題) [carried 2x]
- [ ] 新 workflow `rerank-eval.yml` を一度 workflow_dispatch で初回実走確認(配線の初検証)
- [ ] 旧 Session ページ群の体裁リトロフィット(再保存で自動反映) [carried 6x]
- [ ] 小粒: `extract.sh` が `<teammate-message>` を人間 turn に計上・`digest` の index 列挙化・`release.yml` の version/test ゲート・CI の setup-python@v5 が Node20 deprecation 警告(非ブロッキング)

## Decisions
過去の判断・理由・却下案は [Decisions DB](https://app.notion.com/p/128c8c81e60d4443a82cabfd84eb243f) を参照。実装前に `/iroha:recall <topic>` で確認(UserPromptSubmit フックがローカル BM25 で関連決定を常時先出し)。
