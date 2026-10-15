# InGoodPaste! kobito シリーズ再編に伴う変更設計書

kobito シリーズは「各アプリが単体で完結し、kobito-workspace に並べて使える」形に作り替えます。InGoodPaste! は Swift のネイティブアプリのまま残し、workspace の中には表示しません。ほかのアプリとは、kobito-workspace の約束（データの形）だけでつながります。

参照（シリーズについての記述は、すべてこちらにあります）：

- `../kobito-workspace/docs/ARCHITECTURE.md`：シリーズ全体の構成
- `../kobito-workspace/docs/CONTRACTS.md`：アプリ間の約束①〜⑦と、名指ししない規則

## 1. 変更の一覧

| # | 変更 | 理由 |
|---|---|---|
| 1 | ほかのアプリの名前と、組み合わせの説明を、コード・画面・README・文書から消す | 名指ししない規則。アプリが増減しても InGoodPaste! を直さずに済む |
| 2 | 特定のアプリへ送る機能を、⑦ 受け渡しの「送る」に一般化する | 送り先を、起動情報（④）の `receive` から実行時に決める |
| 3 | 特定のアプリ向けの書き出し（F-17）を、「workspace に残す」とカード（③）に変える | 書き出し先のアプリがなくなる。workspace の HOME・カレンダー・検索にクリップを出す |
| 4 | 基準パスの候補を、⑥ 基準パスの履歴から得る | 特定のアプリの設定ファイルを読まないようにする |
| 5 | 自分の起動情報（④）を書き出し、`kobito://ingoodpaste/…` を受け付ける | workspace のカードから InGoodPaste! を開けるようにする |

`Companions/Dataset.swift`（⓪-1）と `Companions/TagStore.swift`（⓪-2）の動作は、今の約束どおりなので変えません。コメントの書き換えだけを行います。

## 2. ほかのアプリの名前を消す

- README には「kobito シリーズの1つ。ほかのアプリとの連携は kobito-workspace を参照」と1行だけ書きます。
- 送り先や連携の可否は、約束（起動情報④）を通して実行時に知ります。

| 今の箇所 | 変更 |
|---|---|
| `README.md`（冒頭の紹介、動作環境、連携の説明） | ほかのアプリの名前を消し、上の1行に置き換える |
| `docs/REQUIREMENTS.md`（F-16・F-17 ほか） | F-16 を「送る（⑦）」、F-17 を「workspace に残す（③）」に書き換え、ほかのアプリの名前を消す |
| `docs/DEVELOPMENT.md` | ほかのアプリの名前を消す。シリーズの規則は kobito-workspace を参照させる |
| `Sources/SettingsWindow.swift`（`SeriesApp` の一覧、連携の説明、「〜が使っているフォルダが見つかりました」） | `SeriesApp` の一覧を消し、「kobito シリーズについて（kobito-workspace の README を開く）」のリンク1つにする。基準パスの候補は §5 |
| `Sources/Panel/PanelModel.swift`（「〜に残す」「〜の新しいメモにする」「〜の開いているメモに足す」） | §3・§4 の一般化した操作に置き換える |
| `Sources/Panel/PanelController.swift`（`.exportToTomelet`・`.sendToPopNote`） | 同上 |
| `Sources/InGoodPasteApp.swift`（書き出し・送る処理と、その文言） | 同上 |
| `Sources/Companions/PopNoteLink.swift` | `Companions/Share.swift`（⑦）に置き換える（§3） |
| `Sources/Companions/TomeletExport.swift`・`schema/tomelet/`・`scripts/sync-schema.sh` | `Companions/WorkspaceCards.swift`（③）に置き換え、`schema/tomelet/` と写しのスクリプトは消す（§4） |
| `Sources/ClipStore+Organize.swift`・`Settings.swift`・`SQLiteDatabase.swift`・`ClipStore.swift`・`ClipContent.swift`・`PasteStack.swift`・`Panel/Theme.swift`・`Panel/ModeViews.swift`・`Companions/Dataset.swift`・`Companions/TagStore.swift` のコメント・文言 | ほかのアプリの名前を「kobito シリーズ」「共有タグ（tags.json）」などに書き換える |
| `schema/001_initial.sql` のコメント | 同上 |
| `tests/harness/main.swift`・`tests/run.sh` | ほかのアプリを前提にした場面を、約束を前提にした場面に書き換える |
| `scripts/demo/demo.html`・`scripts/social-preview.sh`・`build.sh`・`scripts/make-icon.py`・`scripts/package-release.sh` | ほかのアプリの名前を消す。シリーズ共通のアイコンの描き方は kobito-workspace の `assets/` を参照する |

## 3. 送る（旧 F-16 の一般化）

### 今

`⇧⌘N`（新しいメモにする）と `⇧⌥⌘N`（開いているメモに足す）で、特定のメモアプリへ、文字と画像を一時ファイルの JSON で渡しています。

### 変更後

- パネルに「送る…」（`⇧⌘N`）を置きます。押すと、送り先の一覧が出ます。
- 送り先の一覧は、PC 固有領域の `kobito-tools/apps/*.json`（④）の `receive` を集めて、実行時に作ります。表示は「`name`：`label`」です（例：「〇〇：新しいメモにする」）。
- 一覧に並べるのは、`accepts` に、選んだクリップの中身（`text`・`image`・`file`）のどれかを含む口だけです。
- 最後に使った送り先は覚えておき、`⇧⌥⌘N` で一覧を出さずにそこへ送ります。
- 送り方は ⑦ のとおりです。OS の一時フォルダの `kobito-share/<UUID>.json` に書き、`receive` の `url` の `{file}` を置き換えて、送り先の起動情報の `command` で開きます。
- 送り先が1つも無いときは、「送り先のアプリがありません。kobito シリーズについては kobito-workspace を参照してください」と表示します。
- 文字・画像は ⑦ の `text`・`images` に入れます。ファイルのクリップは `files` に入れます。

## 4. workspace に残す（旧 F-17 の置き換え）

### 今

`⌘S` と「自動で残すタグ」で、その日のクリップを1件のメモにまとめ、ほかのアプリが読む形の DB（`.kobito-tools/InGoodPaste/database/ingoodpaste.sqlite3`、`schema/tomelet/`）に書いています。

### 変更後

- `⌘S` と「自動で残すタグ」の操作は残し、名前を「workspace に残す」にします。
- 残したクリップは、InGoodPaste! 自身の DB に「残した日」と一緒に記録します。ほかのアプリの表の形にそろえる必要はなくなります。既存のデータは移します。
- `<基準パス>/.kobito-tools/InGoodPaste/cards.jsonl` に、**日ごとに1枚のカード**を書き出します。

| 項目 | 値 |
|---|---|
| `kind` | 「クリップ」 |
| `id` | `clips-<YYYY-MM-DD>` |
| `title` | 「10月15日のクリップ」 |
| `date` | その日 |
| `tags` | その日に残したクリップのタグ（重複を除く） |
| `text` | その日に残したクリップの文字（OCR の文字を含む）を、2000 文字まで |
| `url` | `kobito://ingoodpaste/day/<YYYY-MM-DD>` |
| `updated` | その日に最後に残した日時 |

- 画像は今と同じく PNG にそろえて、`.kobito-tools/InGoodPaste/` の下に保存します。カードには画像を入れません。
- workspace を使わない利用者のために、設定でこの機能を隠せるようにします。

## 5. 基準パスの候補

| 今 | 変更後 |
|---|---|
| `SettingsWindow.swift` が、特定のアプリの PC 固有の設定ファイルを読んで基準パスを見つける | ⑥ `~/Library/Application Support/kobito-tools/datasets.json` を読み、「kobito シリーズで使っているフォルダ」を候補として並べる |
| — | 基準パスを開いたら、⑥ に自分の1件（`app: "ingoodpaste"`）を書き込む |

## 6. 起動情報と受け付ける URL

起動のたびに `~/Library/Application Support/kobito-tools/apps/ingoodpaste.json` を書き出します。

```json
{ "app": "ingoodpaste", "name": "InGoodPaste!", "command": ["/usr/bin/open", "-b", "<InGoodPaste! のバンドルID>"] }
```

`embed` と `receive` は持ちません（workspace の中には表示せず、サイドバーの下に「起動する」ボタンとして並びます）。

| URL | 動作 |
|---|---|
| `kobito://ingoodpaste/day/<YYYY-MM-DD>` | パネルを開き、その日に残したクリップで絞り込む |
| `kobito://ingoodpaste/open/<クリップID>` | パネルを開き、そのクリップを選ぶ |

- URL は「URL を開く」Apple Event（`kAEGetURL`）として届きます。`NSAppleEventManager` でハンドラーを登録して受け取ります。
- `open -b <バンドルID> kobito://…` で、`kobito` スキームを Info.plist に登録していなくても、起動中・未起動のどちらでも URL が届くことを確認済みです（kobito-workspace の `spikes/apple-event/`）。ハンドラは `applicationWillFinishLaunching` で登録します（未起動から開かれたとき、`didFinishLaunching` より前に届くため）。`kobito` スキームは Info.plist に登録しません。

## 7. 進める順番

1. 起動情報の書き出しと URL の受け付け（§6）。
2. ⑥ 基準パスの履歴（§5）。
3. 送る（§3）。送り先側の `receive` の対応と同時に確かめる。
4. workspace に残すとカード（§4）。既存のデータの移し替えを含む。
5. ほかのアプリの名前を消す（§2）。
