最新サマリー (2026-06-25): 忖度なしの徹底評価 → 設計・コード・配布は上位（KISS 徹底 / MCP 一本 / selftest 23/23 green / init の DB・ビュー約束が実態と一致）。評価で見つけた4穴のうち read-side で解けるものは即修正（testing.md 実態化 / SKILL プロパティ型明記 / recall 古い要約ガード / Decision 昇格基準、2コミット）。残りは別プロジェクト／データ量待ち。総合 78/100（B+）。

直近セッション:
- 2026-06-25 — 徹底評価とドッグフーディング再開 — Complete
- 2026-06-24 — Notion 連携の設計と Phase 1 実装 — WIP

未完了 / 次にやること:
- [3回繰越] 2個目以降のプロジェクトを /iroha:project で登録（横断検索が活きる）
- Phase 3（任意）: SessionEnd 自動保存 / 検索のスケール検証
- 〔見送り〕手動トリガーの取りこぼし対策 — SessionStart の未保存リマインドで足り、Stop ブロックは方針外（YAGNI）

決定・各回の記録・スタックの正本は Notion（Decisions / Sessions / Projects DB）。このミラーには転記しない。
