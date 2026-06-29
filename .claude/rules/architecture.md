# アーキテクチャ不変条件

- **Notion 連携は MCP 一本**。書き込みは Claude がスキル内で Notion MCP ツールを呼ぶ:
  `notion-create-database` (DB 作成) / `notion-create-pages` (DB 行 + Markdown 本文) /
  `notion-update-page` (`replace_content` で State 全置換) / `notion-search` (リコール、無料プランで動く)。
  **API トークンは使わない**。認証は MCP の OAuth のみ (配布ユーザーは MCP 接続だけ)。
- **relation プロパティは使わない**。MCP の relation 書き込みに既知バグ (makenotion/notion-mcp-server
  Issue #45)。Session↔Decision **および Session↔PR** は **URL プロパティ**で連結 (Sessions DB の
  `PR` URL カラム)。安定確認後にネイティブ relation へ昇格可。
- **決定論抽出は TypeScript (Bun)**。`scripts/extract.ts` が transcript JSONL から
  files / commands / meta / **prompts**(人間の実発言) / **stats**(メトリクス) /
  **tools**(ツール内訳) / **chat**(整形フルチャット・1ターン上限) を read-only で抽出
  （壊れ/切り詰め行は行ごとの `try/catch JSON.parse` でスキップし全滅させない）。stdout = 要求されたビューのみ、
  診断ログは **必ず stderr**。会話ハイライトの **You は `prompts` の実発言にアンカー**し、
  Claude が発言を創作しない／成功を誇張しない。**`extract.ts` は pure-local・ネットワーク禁止**
  (絶対に hang/失敗で save を壊さない)。唯一のネットワーク接触は `scripts/_lib/gh.ts` に隔離する:
  `gh pr list --head <branch>` を**単発・ハードタイムアウト・リトライ無し**(CI-discipline) で叩き、
  **gh 不在/未認証/オフライン/PR 無しは全て fail-soft で `[]`** に縮退して save を決して止めない。
  Session↔PR はこの 1 リンクだけ (PR DB も recall 統合も GitHub 側書き込みもしない＝Phase 0 / KISS)。
  `IROHA_GH_BIN` で gh バイナリを差し替え可能＝テストは実 gh/ネットワーク無しで fail-soft とパースを検証。
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
  名指しで誘導する (初見の到達性)。**ルートのガイドは一行ベタ書きにせず**「どこに何があるか」の箇条書き＋
  メタ callout に分け、加えて **linked chart view のダッシュボード**(Sessions 推移/Type・Decisions
  Topic/Status)を載せてデータが溜まるほど可視化される (init が生成＝再 init/配布で再現)。MCP で callout/
  list を挿入する時は **real newline/tab を使う**(`\n`/`\t` の2文字は `nt`/`n` として leak＝State publish
  と同じ罠)・挿入後は `fetch` で leak を検証。**Notion に出す prose は発行前に必ず `link-lint.ts` を通す**
  (backtick 外の裸ファイル名/パス=`extract.ts`/`CLAUDE.md` 等を Notion が `http://…` に自動リンク化する罠を、
  人間の注意力でなく決定論ゲートで根治＝`state-lint` と同形)。save/init/project/digest の発行点に配線し
  selftest で守る。**Session 本文の構造 (必須 `## ` セクション=Metrics/Decisions/Progress/Highlights/
  Details の存在・順序・escape leak) は `session-lint.ts` が publish 前にゲートする (`state-lint` の
  Session 版＝構造のみを守り、捏造=Highlights 創作は LLM 領域で prompts/chat 抽出を地上の真実に縛る)。
  save の Session content temp file に link-lint と並べて配線し bun test で守る。**
- **3層メモリ**: Session=各回の出来事 / Decision=なぜ / **Projects (Architecture)=今の技術スタック**
  (言語・lib・CI・mermaid 図、手動更新 `/iroha:project`)。Projects は 1 行=1 プロジェクトの共有 DB、
  `Languages` のみ multi_select、横断検索 (同言語/同 lib の他プロジェクト) に使う。Architecture には
  「なぜ」を書かず Decisions へリンク。
- **capture は 2 経路** (Decision 行を作る正本は同一)。①重い `/iroha:save-session` = 各回の全記録
  (chat/metrics/highlights/State carry-over ＋ その回の Decision 群)。②軽量 `/iroha:decide` = 決定 1 件を
  その場で 1 行 1 write (理由＋却下案、Topic/Project の SELECT ensure・dedup/supersede・index upsert は
  save §5.0/§6 の部分集合)。**Session 行も State も触らない** (=決定台帳だけを育てる)。北極星「育つ記憶」は
  full save の頻度に依存しない: 決定の瞬間に台帳が伸びる。save と decide が作る Decision 行のスキーマ・
  dedup 規律・index 形式は同一 (二経路で別物を作らない)。
- **リコールは2段だがローカルにモデルを持たない**。①常時の**安価ローカル前段**=
  `scripts/_lib/recall.ts :: recallLocal` = `search.ts` の自前 **BM25**(TS・CJK 2-gram トークナイズ・
  status/type 重み・英語機能語ストップワード除去=recall 中立で romaji 識別子 `iroha-for-memory` 由来の
  "for" 等が cross-domain 偽一致するのを根治)。LLM もネットワークもモデルも要らず即時・オフライン・**無依存**で、
  UserPromptSubmit hook が毎プロンプト proactively に注入する。precision は意図的に deferred=後段の semantic
  段の仕事。同一語彙の偽陽性 leak は固有限界として許容し floor は上げない・**coverage gate も入れない**
  (どちらも**単一強語マッチの実 recall を犠牲**にし recall-sacrosanct に反する: coverage≥2 は selftest の
  `oauth flow`→`s1`=doc が `oauth` のみ含む単一トークン正答を落とすことで実証済)。**ただし cold-start の
  コーパスサイズ gate は別物として許可する** (`recallLocal`、既定 `IROHA_RECALL_MIN_CORPUS=8`、1=実質 off):
  index 行数が閾値未満の間だけ前段 tier 全体を黙らせる。これは floor 引き上げでも per-query coverage gate でも
  ない (どちらも**十分なコーパスでも**実 recall を恒久的に削る) — 極小コーパスでは BM25 IDF が誤較正で
  「実マッチ ~0.96<floor=MISS / 無関係マッチ ~5.5=誤注入」(5 行で実測) になるため、IDF が信号と偶然を分離できる
  大きさに**育つまで**沈黙する方が「自信ありげな偶然一致」より良い。コーパスが育てば**自動解除**され (内部の
  per-query スコアリングには一切触らない)、`/iroha:decide` がその成長を速める。明示 `/iroha:recall` は
  コーパスサイズに関わらず常に動く。②深い**semantic 後段**=
  `/iroha:recall` が `notion-search`(無料 workspace で自分のページに scoped＝iroha が要るのはこれだけ。完全な
  semantic ランクは Notion AI が要る場合あり)で言い換えも拾い、`notion-fetch` で Rationale/Alternatives/
  変更ファイルまで合成する。**この後段は `context: fork` の subagent** で走らせ、大量の中間読み(複数 DB の
  notion-search・本文の notion-fetch・index 列挙)でメイン文脈を汚さず curated な答えだけ返す。前段で足りる時は
  後段を起動しない(コスト/遅延ゼロ)。index 全件列挙(`query-data-sources` が有料＝列挙不能を補完)で dedup・
  abstention・audit を**完全**に行う。`/iroha:recall` は relevance+recency+importance で少数を edges-first に
  返す(該当無しは正直に abstain)。supersede は `トピック:` 前方一致＋index、加えて search.ts の近傍検索で別
  トピック名の重複も拾う。品質は `recall-eval`(BM25 recall)/`recall-scale`(スケール)で **golden set**
  (`tests/golden-recall.txt`)を**凍結 fixture コーパス**(`tests/fixtures/recall-corpus/.iroha/index.ndjson`)に
  対して計測する。生きた index に結合させない=ワークスペース再 save で決定 id が churn しても golden が
  ドリフトせず CI が落ちない(過去3回 red になった真因を根治)。fixture 再生成は意図的に行う時だけ。
- **ローカル dense embed / cross-encoder rerank の HEAVY tier は撤去した**(旧「リコールは2段(HEAVY tier)」
  「HEAVY を Bun in-process 化」決定を **supersede**)。理由: 小コーパス(決定数十件)で BM25 ≈ dense、
  cross-encoder は terse 日本語で実マッチに ~0 を返すバイモーダルで効果が薄く、transformers.js＋数百MB×2
  モデルで install が重い。そして深い semantic は後段の `notion-search` が**無料・install 不要**で担うため
  ローカルモデル tier は冗長＝過剰実装だった。前段=無依存 BM25、後段=notion-search で必要十分。
  `scripts/embed.ts` / `scripts/rerank.ts` / `scripts/rerank-setup.ts` / `tests/hybrid-eval.ts` /
  `tests/rerank-eval.ts` と transformers.js 依存・モデル DL・`rerank_enabled` flag を全廃し、プラグインは
  **真の zero-install** に戻した(`recall.ts` は BM25 への薄い wrapper)。
- **FREE BM25 を外部 lib に置換しない (2026 調査済)**。`search.ts` は MiniSearch/Orama 等で置換可能だが、
  lib が肩代わりするのは BM25 算術 ~40 行のみで **CJK 2-gram tokenizer と importance 重み(decision>session・
  Active>Superseded)は結局自前**＝依存追加の純損 (KISS/YAGNI・世界配布で依存最小)。将来オプション: スケール
  時の MiniSearch 移行。
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
  ミラーする。`/iroha:history <topic>` が現行 Active から `index.ts chain` で「v3←v2←v1」を offline に
  辿り、各段の理由を notion-fetch で合成して**決定の進化を物語として**見せる。`supersedes` の指す id が
  index に無い時は `integrity.ts` が **broken lineage** として緑のまま通さない。Session ページのセクション
  構造は固定 (Metrics ダッシュボードは常設、任意は
  Architecture / Rules changed / Failures の 3 つ)。
- **冪等性**: `/init` は既存コンテナ/DB を検出したら再利用 (チーム参加 = 同じコマンド)。
  fallback = 複製可能 Notion テンプレート方式。
- **シークレットを持たない**。Notion 認証は MCP OAuth で完結。userConfig / env トークンは無し。
- **保存はリマインド・recall は proactive (ローカル)**。保存強制はしない (Stop の exit 2 ブロックは
  使わずユーザーを閉じ込めない)；保存忘れは SessionStart で注意喚起。一方 recall は **UserPromptSubmit
  のローカル注入** (`recall-inject.ts` が `search.ts` の BM25 を回し関連決定を proactively 注入)。
  加えて **write-time の自発チェック**: `check-inject.ts` (PreToolUse, `if: Bash(git commit *)`) が
  commit 直前にコミット subject＋ステージ paths で同じローカル recall を回し、その領域を支配する
  **Active 決定**を advisory 注入する (「reverse していないか /iroha:check で確認を」)。**ブロックしない**
  (`additionalContext` のみ・`permissionDecision` 無し＝exit 0 で通常の許可フロー維持、commit を自動
  承認しない)。prompt-time recall が発火しなかった/忘れた変更を、コードが landing する最後の関所で拾う。
  ゲートは recall-inject と同形 (`IROHA_CHECK_DISABLE=1`・consent・abstain・subject 毎 session cache)。
  判断 (本当に矛盾か) は LLM の仕事＝hook はしない (LLM-in-hook 反パターンを踏まない)。
  毎プロンプト headless `claude -p` を起動する旧設計は撤廃 (SOTA に無い反パターン＝コスト/遅延/レート
  競合、`claude`/`timeout` 依存、非ユーザー turn での誤発火があった)。新設計は LLM もネットワークも呼ばず
  即時・オフライン。fail-safe は維持: `IROHA_RECALL_DISABLE=1` で停止、`recall_enabled`(init で arm)未設定や
  ゲート該当(短文/slash/`<task-notification>` 等の擬似プロンプト)やマッチ無し(floor 未達)では
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
