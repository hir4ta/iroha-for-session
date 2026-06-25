**Latest (2026-06-25):** 反復評価で総合80/100、前回 rot 3件の根治が定着を実データで実証。最大ギャップ「書き込み経路が無テスト」に State 発行前バリデータ `state-lint.sh` を新設し、再発クラス(エスケープ漏れ/セクション欠落)を検出→予防へ（save-session §8/audit §D に配線、selftest が実 mirror を恒久ガード）。selftest 72→78・recall-eval 100%・scale 8/8 全 green・1 commit。

## Recent sessions
- [2026-06-25 — 評価とState発行前ガード](https://app.notion.com/p/38a822c6938a810b86d7f1f2f256e101)
- [2026-06-25 — トラスト根治とスケール実証](https://app.notion.com/p/38a822c6938a8189b9e6f5c84d304efa)
- [2026-06-25 — ローカルBM25リコール再設計](https://app.notion.com/p/38a822c6938a816092e3fb101f391cdb)
- [2026-06-25 — 90点ロードマップ実装と検証](https://app.notion.com/p/38a822c6938a813a9968ef7b2375b86b)
- [2026-06-25 — 徹底評価とドッグフーディング再開](https://app.notion.com/p/38a822c6938a812c92e2e40b02e39b13)

## Unfinished / Next
- [ ] 旧 Session ページ群の体裁リトロフィット（低優先・再保存で自動反映）[carried 2x]

見送り中（正本は Decisions DB・必要性が実測で出たら再評価）: Session の property map 検証（ファイル化＝アーキ変更が要る）/ リコール効果の計測ループ / git 現実×Decision 矛盾検知 / SessionEnd 自動保存 / importance 学習 / reflection 層。

## Decisions
過去の判断・理由・却下案は [Decisions DB](https://app.notion.com/p/128c8c81e60d4443a82cabfd84eb243f) を参照。実装前に `/iroha:recall <topic>` で確認（UserPromptSubmit フックがローカル BM25 で関連決定を常時先出し）。
