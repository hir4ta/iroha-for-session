最新サマリー (2026-06-25): 忖度なしの徹底評価を実施。設計・コード・配布は上位（KISS 徹底 / MCP 一本 / selftest 23/23 green / 配布準備済み）。一方 Sessions DB が1件で停滞し「育つ記憶」が未実証と判明 → 本セッションを2件目として保存し dogfooding を再開。総合 78/100（B+）。

直近セッション:
- 2026-06-25 — 徹底評価とドッグフーディング再開 — Complete
- 2026-06-24 — Notion 連携の設計と Phase 1 実装 — WIP

未完了 / 次にやること:
- Session の失効戦略を決める（古い要約が recall を汚す問題）
- .claude/rules/testing.md を実態に修正（「HTTP 組み立て関数の出力 JSON 検証」は MCP 一本化で死文化）
- Decision 昇格基準を1行明文化（表示・命名の微調整は Decisions DB に出さない）
- 手動トリガーの取りこぼし対策（未保存 N 件で強めリマインド。Stop ブロックはしない）
- [2回繰越] 2個目以降のプロジェクトを /iroha:project で登録（横断検索が活きる）
- Phase 3（任意）: SessionEnd 自動保存 / 検索のスケール検証

決定・各回の記録・スタックの正本は Notion（Decisions / Sessions / Projects DB）。このミラーには転記しない。
