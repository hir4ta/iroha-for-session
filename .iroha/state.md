**Latest (2026-06-25):** 一次監査(コード全読＋Notion実データ＋テスト実走＋recall実測)でデータ品質は高いと確認する一方、忖度なしで「数セッション連続の自己評価ループ・北極星(横断記憶)がN=1で未実証・recall前段precisionの構造的限界(領域外クエリの誤注入をscore13.69で実測)」を指摘。N=1前提の一手として保存リマインダを「最後の保存以降の実体ある未保存セッション全件＋trivial除外」へ強化(自動保存:当面見送りと整合・無人保存せず)。selftest 80→82全green・1commit push・/iroha:check自差分all-clear。

## Recent sessions
- [2026-06-25 — 評価と保存バックログ実装](https://app.notion.com/p/38a822c6938a811eb58ad62cc504920a)
- [2026-06-25 — 評価とState発行前ガード](https://app.notion.com/p/38a822c6938a810b86d7f1f2f256e101)
- [2026-06-25 — トラスト根治とスケール実証](https://app.notion.com/p/38a822c6938a8189b9e6f5c84d304efa)
- [2026-06-25 — ローカルBM25リコール再設計](https://app.notion.com/p/38a822c6938a816092e3fb101f391cdb)
- [2026-06-25 — 90点ロードマップ実装と検証](https://app.notion.com/p/38a822c6938a813a9968ef7b2375b86b)

## Unfinished / Next
- [ ] 旧 Session ページ群の体裁リトロフィット（低優先・再保存で自動反映）[carried 4x]
- [ ] `save-session` step2 の transcript locate を glob から cwd ハッシュ絶対パスへ決定論化（本セッションで空/約2分ハングを実測・前回も再発）

見送り中（正本は Decisions DB・必要性が実測で出たら再評価）: recall precision の本質対策(no-token不変を破壊) / 横断記憶の実証(2つ目の実プロジェクト/2人目=コードでない) / SessionEnd 自動保存 / importance 学習 / reflection 層。評価ループ脱出には「機能追加」でなく外部検証が要る(N=1では precision 誤注入も実害小)。

## Decisions
過去の判断・理由・却下案は [Decisions DB](https://app.notion.com/p/128c8c81e60d4443a82cabfd84eb243f) を参照。実装前に `/iroha:recall <topic>` で確認（UserPromptSubmit フックがローカル BM25 で関連決定を常時先出し）。
