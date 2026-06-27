**Latest (2026-06-27):** iroha を4視点レビュー＋全削除→再 init で徹底改善後、GitHub 拡張(PR ライフサイクル記憶)の最高到達地点を3エージェント議論で確定(`gh` は `/iroha:pr` 限定の gated 依存・別 recall レーン・flaky 判定せず再発カウント・着手は N=1 脱出後)。リポジトリを `iroha-for-session` にリネーム完了(GitHub repo + 配布 URL/名 + machine-local: 作業 dir・`$HOME/.iroha`・config rekey・repo 内識別子)。recall に英語機能語ストップワード除去を追加(romaji 由来の cross-domain leak を根治・recall 中立)。総合の天井=N=1 外部未実証は不変。

## Recent sessions
- [2026-06-26 — iroha 徹底改善と再構築](https://app.notion.com/p/38c822c6938a81ea9ec6eff92aeb46dc)

## Unfinished / Next
- [ ] **N=1 脱出**(最優先): 非 iroha / 非日本語の実プロジェクトで iroha 全体を実証(総合の天井を上げる唯一の手)。mumei 実使用が端緒。
- [ ] **GitHub 拡張 Phase 0**(N=1 脱出の後に着手): `pr-extract.sh`(`gh` 境界付き抽出)+golden eval・Session↔PR の URL 連結・別 recall レーン機構・thread→Decision synthesis。設計は決定「GitHub拡張: gated・defer」に確定済。
- [ ] リネームの Notion 残務(任意・低優先): State ページタイトルが `State — iroha-for-notion` のまま(cosmetic)。`Project` オプション `iroha-for-session` は次回 save で ensure-option が自動追加(過去行は正直に旧名のまま)。
- [ ] 空ページ「iroha」(`38c822c6938a81e78899e6aef2081ec1`)を UI でゴミ箱へ(MCP はページ削除不可)。
- [ ] init step9 の real-newline/fetch 検証を実 init 1回でスモーク確認(本セッションで手動実行は確認済)。
- [ ] 小粒: `digest` の index 列挙化(`query-data-sources` 有料を補完)。selftest の `ci-*` 系で出る既存の jq stderr ノイズ(無害・141 pass・recall 機能)も整理可。

## Decisions
過去の判断・理由・却下案は [Decisions DB](https://app.notion.com/p/792a2ae4dda947fbb7e008a7d05dece2) の **Active ビュー**(俯瞰は **By Topic**)を参照。技術スタックは [Projects DB](https://app.notion.com/p/f3eba8e5e8844a939e94082c9e1d589b)。実装前に `/iroha:recall <topic>` で確認(UserPromptSubmit フックがローカル BM25 で関連決定を常時先出し)。
