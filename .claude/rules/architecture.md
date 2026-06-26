# アーキテクチャ不変条件

- **Notion 連携は MCP 一本**。書き込みは Claude がスキル内で Notion MCP ツールを呼ぶ:
  `notion-create-database` (DB 作成) / `notion-create-pages` (DB 行 + Markdown 本文) /
  `notion-update-page` (`replace_content` で State 全置換) / `notion-search` (リコール、無料プランで動く)。
  **API トークンは使わない**。認証は MCP の OAuth のみ (配布ユーザーは MCP 接続だけ)。
- **relation プロパティは使わない**。MCP の relation 書き込みに既知バグ (makenotion/notion-mcp-server
  Issue #45)。Session↔Decision は **URL プロパティ**で連結。安定確認後にネイティブ relation へ昇格可。
- **決定論抽出は bash**。`scripts/extract.sh` が transcript JSONL から
  files / commands / meta / **prompts**(人間の実発言) / **stats**(メトリクス) /
  **tools**(ツール内訳) / **chat**(整形フルチャット・1ターン上限) を read-only で抽出
  （壊れ/切り詰め行は `fromjson?` でスキップし全滅させない）。stdout = 要求されたビューのみ、
  診断ログは **必ず stderr**。会話ハイライトの **You は `prompts` の実発言にアンカー**し、
  Claude が発言を創作しない／成功を誇張しない。
- **知性は Claude 本体 (スキル内)**。要約・決定抽出・Type 分類は `/save-session` の中で Claude が行う。
  コードから Anthropic API を呼ばない。
- **append 非対応を前提に設計**。Session ページ = 作成のみ (1 回で全部書く)、Project State = 毎回
  `replace_content` で全置換。逐次 append はしない。
- **データモデル**: Sessions + Decisions + Projects の **3 DB** + プロジェクト 1 枚の State ページ。
  ID は config.json にキャッシュ。**決定/ルールの正本は Decisions DB / CLAUDE.md** に一本化し、
  State / Session ページに全文転記しない (重複防止)。
- **コンテナ構造は flat 蓄積を作らない**。container 直下は *ガイド callout + 3 DB + `States` フォルダ
  + `Digests` フォルダ* だけ。**State ページ (プロジェクト毎 1 枚) は `States` フォルダ配下、Digest
  ページ (実行毎) は `Digests` フォルダ配下**にぶら下げる — でないと参加プロジェクト数・digest 実行数
  だけ container 直下に flat に増えて junk drawer 化する。`states_folder_id` / `digests_folder_id` を
  config.json にキャッシュ (init が作成・team-join で再利用、旧 workspace には欠落時に作成して既存を移動)。
  fallback: folder id が空 (folder 導入前の workspace) なら container 直下に作る。
  **State と Projects 行は同じプロジェクトの別側面だが分離して持つ** (State=auto・毎 save・現在地 /
  Projects=manual `/iroha:project`・恒久スタック)。カデンツも責務も違うので**畳まず相互リンク**で繋ぐ:
  State の `## Decisions` 節が Projects 行へ、Projects 行 callout が State へリンクする。container
  callout は最重要の **State ページを名前でなくリンク**で出し、決定は Decisions の **`Active` view** に
  名指しで誘導する (初見の到達性)。
- **3層メモリ**: Session=各回の出来事 / Decision=なぜ / **Projects (Architecture)=今の技術スタック**
  (言語・lib・CI・mermaid 図、手動更新 `/iroha:project`)。Projects は 1 行=1 プロジェクトの共有 DB、
  `Languages` のみ multi_select、横断検索 (同言語/同 lib の他プロジェクト) に使う。Architecture には
  「なぜ」を書かず Decisions へリンク。
- **リコールは2段 (Adaptive-RAG ルーティング)**。①常時の**安価ローカル前段**=
  `scripts/_lib/recall.sh :: iroha_recall_local`。**FREE tier**(既定・無依存)= `search.sh` の
  pure-jq **BM25**(CJK 2-gram トークナイズ・status/type 重み)。LLM もネットワークも要らず即時・
  オフライン・無料で、UserPromptSubmit hook が毎プロンプト proactively に注入する。**HEAVY tier**
  (opt-in・`rerank_enabled`=true で arm)= **BM25 ∪ dense**(`scripts/embed.mjs`=ローカル bi-encoder
  `multilingual-e5-small`)で候補生成し、cross-encoder(`scripts/rerank.mjs`=`bge-reranker-v2-m3`)が
  **強い意味一致を BM25 advisory の上に promote する(veto はしない)**。理由: cross-encoder はこの
  terse な日本語コーパスで**バイモーダル**(近言い換えは>0.4、希少な実マッチ「連結: relation でなく
  URL」は~0.003 で off-topic と区別不能)。veto 設計は実マッチを黙って落とし**recall を犠牲**にする
  (旧 rerank tier がそうで、BM25 専用の recall-eval が end-to-end を測らず盲点化していた)。よって
  BM25 ヒットは sacrosanct(recall=北極星)、dense は候補生成漏れ(=今まで直せなかった MISS)を**足す**だけ。
  結果は単調(hybrid recall ≥ BM25 recall)。同一語彙の偽陽性 leak は BM25/dense/合意/cross-encoder の
  どれでも実マッチと分離不能=固有限界として**正直に計測**(`hybrid-eval.sh` が soft-leak を報告)、
  ただし advisory なので低害(floor は上げない)。②深い**semantic 後段**= `/iroha:recall` が
  `notion-search`(無料で動く)で言い換えも拾い、`notion-fetch` で Rationale/Alternatives/変更ファイル
  まで合成する。前段で足りる時は後段を起動しない(コスト/遅延ゼロ)。index 全件列挙(`query-data-sources`
  が有料＝列挙不能を補完)で dedup・abstention・audit を**完全**に行う。`/iroha:recall` は
  relevance+recency+importance で少数を edges-first に返す (該当無しは正直に abstain)。
  supersede は `トピック:` 前方一致＋index、加えて search.sh の近傍検索で別トピック名の重複も拾う。
  品質は `recall-eval`(FREE tier=86%)/`hybrid-eval`(HEAVY tier=93%・MISS 回復・abstention 100%・
  soft-leak 報告)/`rerank-eval`(cross-encoder 単体精度)で**重なる golden set**(`tests/golden-recall.txt`)
  を計測し、評価の盲点(tier 毎に別 set で回帰を隠す)を作らない。
- **repo ミラーは `.iroha/state.md`（State 全文）と `.iroha/index.ndjson`（keys＋検索snippet）の 2 つ**
  （ともに commit し teammate は pull で共有）。SessionStart hook は Notion 非到達なので `state.md`
  を注入。**決定の本文はローカルに持たない**（Notion 正本）。index は id/topic/status/date に加え、
  rationale/summary を ≤160 字に畳んだ**派生検索 snippet**(`text`)を持つ＝BM25 が決定の*理由*に当てる
  ための検索キー。本文の正本は Notion で、snippet は save 毎に再生成される(embedding 同様の派生物)ので
  二重の真実にならずドリフトしない。recall は full text を `notion-fetch` で正本から取る。
  config.json / saved マーカーは $HOME (マシン固有)。State の未完了は save 毎にトリアージ。
- **命名と履歴**: Session = `YYYY-MM-DD — 主題`、Decision = `トピック: 選択` (理由は Rationale、
  却下案は Alternatives 欄)。**`トピック` は Decisions の一級 SELECT プロパティ**(`Name` から parse
  でなく明示) ＝ supersede グルーピングを enum 一致で堅くし、Notion の `By Topic` board view で
  決定ファミリーを俯瞰できる。`Project` 同様 write で auto-create されないので save が新トピックを
  ALTER で足す(5.0 と同形)。近義の別トピック名を作らず既存を再利用し family を分散させない。
  決定を覆す時は旧行を **Status=Superseded** にし上書きしない (心変わりも
  記憶)。新決定本文に `Supersedes [旧トピック: 旧選択](url) — 一言` の人間可読 lineage 行を1行置く
  (URL プロパティは裸リンクで何を覆したか見えないため)。**supersede は lineage edge を張る**: 新決定の `Supersedes` プロパティ=置換した旧決定の
  **URL**(relation 回避＝Session↔Decision と同じ URL 連結)、index は同じ辺を `supersedes`(旧 id)で
  ミラーする。`/iroha:history <topic>` が現行 Active から `index.sh chain` で「v3←v2←v1」を offline に
  辿り、各段の理由を notion-fetch で合成して**決定の進化を物語として**見せる。`supersedes` の指す id が
  index に無い時は `integrity.sh` が **broken lineage** として緑のまま通さない。Session ページのセクション
  構造は固定 (Metrics ダッシュボードは常設、任意は
  Architecture / Rules changed / Failures の 3 つ)。
- **冪等性**: `/init` は既存コンテナ/DB を検出したら再利用 (チーム参加 = 同じコマンド)。
  fallback = 複製可能 Notion テンプレート方式。
- **シークレットを持たない**。Notion 認証は MCP OAuth で完結。userConfig / env トークンは無し。
- **保存はリマインド・recall は proactive (ローカル)**。保存強制はしない (Stop の exit 2 ブロックは
  使わずユーザーを閉じ込めない)；保存忘れは SessionStart で注意喚起。一方 recall は **UserPromptSubmit
  のローカル注入** (`recall-inject.sh` が `search.sh` の BM25 を回し関連決定を proactively 注入)。
  加えて **write-time の自発チェック**: `check-inject.sh` (PreToolUse, `if: Bash(git commit *)`) が
  commit 直前にコミット subject＋ステージ paths で同じローカル recall を回し、その領域を支配する
  **Active 決定**を advisory 注入する (「reverse していないか /iroha:check で確認を」)。**ブロックしない**
  (`additionalContext` のみ・`permissionDecision` 無し＝exit 0 で通常の許可フロー維持、commit を自動
  承認しない)。prompt-time recall が発火しなかった/忘れた変更を、コードが landing する最後の関所で拾う。
  ゲートは recall-inject と同形 (`IROHA_CHECK_DISABLE=1`・consent・abstain・subject 毎 session cache)。
  判断 (本当に矛盾か) は LLM の仕事＝hook はしない (LLM-in-hook 反パターンを踏まない)。
  毎プロンプト headless `claude -p` を起動する旧設計は撤廃 (SOTA に無い反パターン＝コスト/遅延/レート
  競合、`claude`/`timeout` 依存、非ユーザー turn での誤発火があった)。新設計は LLM もネットワークも呼ばず
  即時・オフライン。fail-safe は維持: `IROHA_RECALL_DISABLE=1` で停止、`recall_enabled`(init で arm)未設定や
  jq 不在やゲート該当(短文/slash/`<task-notification>` 等の擬似プロンプト)やマッチ無し(floor 未達)では
  無害に無注入。hook の注入テキスト（wrapper）は **配布コードなので英語**、本文の State/決定は会話言語
  （= ユーザーデータ）。未完了 `- [ ]` 件数のバナーも算出して添える。
  `source=compact`（`/compact`・auto-compact 後）は現在セッションのトランスクリプトから会話
  (prompts ＋ chat 直近) を再注入してスレッドを復元する（行単位 cap でマルチバイト非分割。Notion
  非到達の不変は維持＝ローカル transcript のみ読む）。
- **派生スキルは正本を汚さない**。`/iroha:digest` (期間ロールアップ)・`/iroha:audit`
  (記憶の健全性監査=重複決定/State ドリフト/陳腐化/broken lineage の検出)・`/iroha:history`
  (決定の supersede 連鎖を辿る) は読むだけ (`notion-search`/`notion-fetch`/index)。
  digest は `Digests` フォルダ配下に使い捨ての Digest ページを 1 枚書く (専用 DB は作らない)。audit の
  修正系は `--fix`/確認時のみ、削除でなく `Status=Superseded`/欠落 `Supersedes` 補完 等の
  **可逆操作**に限る。
