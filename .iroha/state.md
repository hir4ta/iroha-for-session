**Latest (2026-06-28):** save の保存処理を機械化。Session 本文を決定論で組み立てる `compose-session.ts` を新設し、Claude は要約・決定などの中身（intel JSON）だけを書けば体裁の整った Notion ページが自動生成されるようにした（手作業の整形と lint の目視往復を撤廃）。方針は「Notion の API トークンは入れず、MCP 接続だけで使える」を維持。`session-lint` のコードスパン誤検知も修正。

## Recent sessions
- [2026-06-28 — save 本文の決定論レンダリング](https://app.notion.com/p/38d822c6938a8168ad5be2856b9a70dc)
- [2026-06-27 — HEAVY recall を Bun in-process 化](https://app.notion.com/p/38c822c6938a8163a391fdddc69a683a)

## Unfinished / Next
- [ ] N=1 脱出: 別プロジェクト mumei で compose 化した新 save フローを実走しフィードバック取得 [carried 2x]
- [ ] 構造ラベルの英語 canonical 化の是非をユーザー確認（今後の保存で表ヘッダ・Done/Unfinished 等が日本語→英語に変わる）
- [ ] State 本文・決定 body（supersede lineage 行）の決定論レンダリングは後回し（YAGNI・小さく既存 lint 済み）
- [ ] GitHub 拡張 Phase 0（N=1 脱出後）: `gh` 境界付き PR 抽出 + Session↔PR の URL 連結 [carried 2x]
- [ ] `rerank-eval` の `TRUEQ` は現コーパス依存 — 決定が増えたら再ラベル/拡張 [carried 2x]

## Decisions
過去の判断・理由・却下案は [Decisions DB（Active ビュー）](https://app.notion.com/p/7544d1820fc247028948855c08becce2) を参照。技術スタックは未登録 — `/iroha:project` で Projects 行を作成すると相互リンクされる。
