最新サマリー (2026-06-25): ローカル recall を毎プロンプト headless から pure-jq BM25(CJK-bigram)二段へ再設計（SOTA/検索の2リサーチ→PM判断）。per-prompt LLM のコスト/遅延/レート競合/誤発火を撤廃し、index に派生検索 snippet を追加。golden 評価ハーネスで Recall@3=100% / MRR0.94 / abstention100% を実証。selftest 59→70 green・recall-eval を CI 常設・4 commits。忖度なし評価は 78/100。

直近セッション:
- 2026-06-25 — ローカルBM25リコール再設計 — Complete
- 2026-06-25 — 90点ロードマップ実装と検証 — Complete
- 2026-06-25 — 徹底評価とドッグフーディング再開 — Complete
- 2026-06-24 — Notion 連携の設計と Phase 1 実装 — WIP

未完了 / 次にやること:
- [ ] [carried 3x] 数百セッション規模での recall スケール検証（index 列挙・BM25 の挙動）
- [ ] 既存 Session ページのハイライト折りたたみリトロフィット（低優先・再保存で自動反映）

決定済み・ロードマップ（正本は Decisions DB）: importance(1-10) / A-MEM リンク進化 / reflection digest / SessionEnd 自動保存 は recall が既に Recall@3=100% のため YAGNI で見送り（lexical 不足や rot 顕在化で再評価）。旧繰り越し `--selfcheck --live` は headless 経路撤廃で陳腐化（selfcheck はオフライン化）。

決定・各回の記録・スタックの正本は Notion（Decisions / Sessions / Projects DB）。このミラーには転記しない。実装前に /iroha:recall で過去の決定・類似実装を確認（フックがローカル BM25 で常時先出し）。
