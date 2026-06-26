**Latest (2026-06-26):** 三度目評価(73/100)から連続改善: ①config妥当性の自己監視で Critical(`decisions_ds_id=DSID`)根治 ②`/iroha:audit` 相当でコンテンツ rot 一掃 ③CI に gitleaks/typos ④cross-encoder rerank(570MB bge-m3)を deploy+実機検証=JP/EN同義語ギャップ(セッション↔SessionEnd)rank1 修正・誤注入0/5 ⑤session recall を実測(良好=distinctive クエリ top1-2。当初「貧弱」は測定 harness バグの誤認と判明し撤回)し recall-eval に4 session ケース追加で測定盲点を解消。selftest 103・recall-eval 13/15(86%)全green・8 commit(未push)。

## Recent sessions
- [2026-06-26 — config自己監視と三度目の評価](https://app.notion.com/p/38b822c6938a81a98378cb726b9c516d)
- [2026-06-26 — 精度rerank前段と完全性自己監視](https://app.notion.com/p/38b822c6938a81869424e9ceb358df3d)
- [2026-06-25 — 評価と保存バックログ実装](https://app.notion.com/p/38a822c6938a811eb58ad62cc504920a)
- [2026-06-25 — 評価とState発行前ガード](https://app.notion.com/p/38a822c6938a810b86d7f1f2f256e101)
- [2026-06-25 — トラスト根治とスケール実証](https://app.notion.com/p/38a822c6938a8189b9e6f5c84d304efa)

## Unfinished / Next
- [ ] rerank の CI 検証(モデル不在で `test:rerank` は今も SKIP)— 軽量モデルを CI に置くか SKIP 許容を明記
- [ ] rerank を非iroha/非日本語の実プロジェクトで実証(iroha では deploy 済・N=1 脱出が残課題) [carried 2x]
- [ ] 旧 Session ページ群の体裁リトロフィット(再保存で自動反映) [carried 6x]
- [ ] 小粒: `extract.sh` が `<teammate-message>` を人間 turn に計上・`digest` の index 列挙化・`release.yml` の version/test ゲート
- [ ] 未 push の 8 commit を push(外向き操作のため保留中)

## Decisions
過去の判断・理由・却下案は [Decisions DB](https://app.notion.com/p/128c8c81e60d4443a82cabfd84eb243f) を参照。実装前に `/iroha:recall <topic>` で確認(UserPromptSubmit フックがローカル BM25 で関連決定を常時先出し)。
