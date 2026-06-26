**Latest (2026-06-26):** 四度目評価(忖度なし70/100)→「KISS無視で徹底的に」を受け 3 波を実装・commit 済: ①opt-in hybrid 検索(BM25 ∪ dense 埋め込み)で rerank を **promote 専用化**し、旧 veto が実マッチ「連結」を黙って落としていた隠れ recall 回帰を根治(hybrid Recall@3 86→93%・abstention 100%・同一語彙 leak も hybrid-eval で正直に計測) ②決定 **lineage** を一級市民化(`/iroha:history`・`Supersedes` URL・index chain・integrity の broken-lineage 検査・実データ 5 連鎖を本文明示分のみ backfill) ③commit 直前の **write-time advisory** フック(PreToolUse・非ブロック・自動承認しない)。selftest 98→121・hybrid-eval 93%・recall-eval 86%・rerank-eval 0 誤注入 全 green。総合の天井=N=1 外部未実証は不変。

## Recent sessions
- [2026-06-26 — hybrid recall・決定lineage・commit check](https://app.notion.com/p/38b822c6938a81d3902ad1f98908ed67)
- [2026-06-26 — config自己監視と三度目の評価](https://app.notion.com/p/38b822c6938a81a98378cb726b9c516d)
- [2026-06-26 — 精度rerank前段と完全性自己監視](https://app.notion.com/p/38b822c6938a81869424e9ceb358df3d)
- [2026-06-25 — 評価と保存バックログ実装](https://app.notion.com/p/38a822c6938a811eb58ad62cc504920a)
- [2026-06-25 — 評価とState発行前ガード](https://app.notion.com/p/38a822c6938a810b86d7f1f2f256e101)

## Unfinished / Next
- [ ] **N=1 脱出**: 非 iroha / 非日本語の実プロジェクトで hybrid・iroha 全体を実証(総合の天井を上げる唯一の手) [carried 3x]
- [ ] Wave 3 の PreToolUse `additionalContext` 非自動承認を**対話モードで実コミット 1 回スモークテスト**(決定論コアは selftest 済)
- [ ] `hybrid-eval.yml`(旧 rerank-eval.yml)を一度 workflow_dispatch で初回実走確認
- [ ] MISS#1「リコールの設計方針」は多答曖昧で未解決(意図的・golden は弄らず)。本筋=リコール系 topic 分散の整理
- [ ] hybrid 93% は opt-in tier の数字・free tier は 86% のまま。opt-in tier 自体が iroha 外で未実証
- [ ] 旧 Session ページ群の体裁リトロフィット(再保存で自動反映) [carried 7x]
- [ ] 小粒: `extract.sh` が `<teammate-message>` を人間 turn に計上・`digest` の index 列挙化・`release.yml` の version/test ゲート・CI の setup-python@v5 が Node20 deprecation 警告(非ブロッキング)

## Decisions
過去の判断・理由・却下案は [Decisions DB](https://app.notion.com/p/128c8c81e60d4443a82cabfd84eb243f) を参照。実装前に `/iroha:recall <topic>` で確認(UserPromptSubmit フックがローカル BM25 で関連決定を常時先出し)。
