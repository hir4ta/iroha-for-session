**Latest (2026-06-26):** iroha を実使用フィードバック＋4視点レビューで徹底改善し、最後にデータを全削除して改善済みスキーマで再 init した回。Notion 構造の整理(`States`/`Digests` フォルダ・決定 `Topic` 一級化・大量データはビューで捌く)、保存効率化(`extract.sh all` 集約)、初回 UX(新規PJ保存の400・gitignore・MCP認証・init事前ページ不要)、トップに読みやすいガイド＋可視化ダッシュボード。recall は単一強語マッチを守るため lexical 据置を再確認(coverage gate は selftest で実 recall 犠牲と実証し却下)。full chat 抽出から teammate-message/compaction summary を除外(人間 turn 誤計上を根治)。selftest 135・recall-eval 86%・CI green。総合の天井=N=1 外部未実証は不変(mumei で実使用は開始)。

## Recent sessions
- [2026-06-26 — iroha 徹底改善と再構築](https://app.notion.com/p/38c822c6938a81ea9ec6eff92aeb46dc)

## Unfinished / Next
- [ ] **N=1 脱出**: 非 iroha / 非日本語の実プロジェクトで iroha 全体を実証(総合の天井を上げる唯一の手)。mumei 実使用が端緒。
- [ ] 空ページ「iroha」(`38c822c6938a81e78899e6aef2081ec1`)を UI でゴミ箱へ(MCP はページ削除不可)。
- [ ] このセッションの Full chat 子ページ(verbatim 監査証跡)を作成(337行と巨大ゆえ別途・`extract.sh chat` から再生成可)。
- [ ] init step9 の real-newline/fetch 検証を実 init 1回でスモーク確認(本セッションで手動実行は確認済)。
- [ ] 小粒: `digest` の index 列挙化・古い `<teammate-message>` 計上は本セッションで根治済。

## Decisions
過去の判断・理由・却下案は [Decisions DB](https://app.notion.com/p/792a2ae4dda947fbb7e008a7d05dece2) の **Active ビュー**(俯瞰は **By Topic**)を参照。技術スタックは [Projects DB](https://app.notion.com/p/f3eba8e5e8844a939e94082c9e1d589b)。実装前に `/iroha:recall <topic>` で確認(UserPromptSubmit フックがローカル BM25 で関連決定を常時先出し)。
