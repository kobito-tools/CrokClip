# 開発について

CorkClip のビルド方法とソースコードの構成をまとめます。利用方法は [README](../README.md)、機能の要件は [REQUIREMENTS.md](REQUIREMENTS.md) を参照してください。

## ビルド

Xcode Command Line Tools（`xcode-select --install`）が必要です。

```bash
./build.sh                                 # フォルダ直下に CorkClip.app（ユニバーサルバイナリ）を作成
./scripts/package-release.sh               # Releases 用の dist/CorkClip_<版>.dmg と dist/CorkClip_<版>_universal.zip を作成
./tests/run.sh                             # 取得から書き戻し・検索・タグ・変換・文字認識・数式・シリーズの約束（起動情報・送る・カード）までのテスト
./tests/preview.sh [書き出す先]            # パネル・設定の画面・メニューバーのアイコンを、アプリを起動せずに PNG に書き出す（既定 .build/preview）
./scripts/make-icon.sh                     # アイコンを描き直す（make-icon.py → icon.svg → icon-1024.png・AppIcon.icns）
./scripts/social-preview.sh [フォント]     # シリーズの紹介画像（assets/icon/CorkClip-1280x640.png）を作り直す（Google Chrome と Noto Sans JP を使う）
```

版番号は `build.sh` の `VERSION` で指定します。ソースから使う人向けの入口は `setup.sh` です（ビルド・アプリケーションフォルダへ移すかの確認・起動情報の書き出し・起動の案内。`--yes`・`--dry-run`・`--help` を受け付けます）。`CorkClip-Setup.command` は `setup.sh` を Finder から動かすための入口です。

`package-release.sh` の dmg は、アプリ・Applications へのリンク・背景（`assets/dmg/`。`scripts/make-icon.sh` で描き直せる）を置き、窓の並べ方を Finder に頼んでから圧縮します。初回は「Finder を操作する許可」を求められることがあります。許可しないと、背景なし（並べ方なし）の dmg になります。

`tests/run.sh` は名前付きの NSPasteboard と一時フォルダを使い、`KOBITO_CONFIG_DIR`・`KOBITO_SHARE_DIR` も一時フォルダに向けるので、実際のクリップボード・履歴・基準パス・シリーズの設定には触れません。数式のテストは同梱の KaTeX を画面外の WKWebView で動かします。`tests/preview.sh` も同じく一時フォルダに見本の履歴を作り、画面外のウィンドウで描いて書き出すので、`CorkClip.app` を起動せずに見た目を確かめられます。

### 許可について

`build.sh` はアドホック署名なので、ビルドし直すたびに macOS からは別のアプリに見え、アクセシビリティと入力監視の許可が外れます。ビルドし直したら、「システム設定」→「プライバシーとセキュリティ」の各項目で CorkClip を一度削除（`−`）してから、もう一度許可してください。

## ソースコードの構成

| パス | 内容 |
|---|---|
| `Sources/CorkClipApp.swift` | 起動、取得した物の流れ（保存 → 自動タグ → スタック → 文字認識 → 自動書き出し）、パネルからの操作、メニューバー、URL、ショートカット |
| `Sources/PasteboardWatcher.swift` | クリップボードの監視（0.3秒ごと）と、保存しない物の判定（F-01, F-02） |
| `Sources/ClipContent.swift` | 1回のコピーの中身（全ての項目・型・データ）、種類の判定、埋め込んだ数式の読み取り、プレビュー、サムネ |
| `Sources/ClipStore.swift` | 履歴のDBと `blobs/` の読み書き、削除、整理（F-01, F-15） |
| `Sources/ClipStore+Organize.swift` | 検索と絞り込み・並べ替え、タグ、ピン、定型文、文字認識の結果、書き出しの印（F-04, F-05, F-08, F-09） |
| `Sources/Paster.swift` | 書き戻しと ⌘V の送信、定型文の差し込み（F-03） |
| `Sources/PasteStack.swift` | ペーストスタックと「スタック N 件」の表示（F-14） |
| `Sources/OCR.swift` | Vision による文字認識（F-08） |
| `Sources/HotKey.swift` | どのアプリでも効くショートカット（Carbon の RegisterEventHotKey） |
| `Sources/Settings.swift` | このMacの設定（`settings.json`）と自動タグの規則 |
| `Sources/SettingsWindow.swift` | 設定の画面（F-19） |
| `Sources/SQLiteDatabase.swift` | macOS 標準の SQLite の薄いラッパーと、`schema/` の適用 |
| `Sources/Panel/` | パネル（フォーカスを奪わない NSPanel。コルクボードの見た目は `Corkboard.swift`・`Theme.swift`）、一覧、プレビュー、作業の画面（タグ・編集・変換・まとめる・数式・定型文）、キー操作、Quick Look、ドラッグ |
| `Sources/Transforms/` | 改行を消す処理、貼る前の変換・パス・まとめる区切り・定型文の差し込み（F-07, F-09, F-11, F-12） |
| `Sources/Latex/` | 数式の元の式と描き方、KaTeX での描画と PDF・PNG・TIFF の作成（F-06） |
| `Sources/Companions/` | 基準パス（`.kobito-tools/`）の扱いと使用中の印・共有タグ（`Dataset.swift`・`TagStore.swift`）、シリーズの約束（`Series.swift`：起動情報・基準パスの履歴・受け付ける URL）、送る（`Share.swift`）、カードに残す（`KeptCards.swift`）（F-04, F-16〜F-18） |
| `Resources/katex/` | 同梱の KaTeX（MIT）と描画ページ `render.html` |
| `schema/` | 履歴のDBの作成と更新（ファイル名順に、まだの物だけ適用） |
| `schema/kept/` | 基準パスの、カードに残したクリップのDBの作成と更新 |
| `kobito-app.json` | kobito シリーズの目印（下の「約束の確かめ」） |
| `tests/` | `run.sh` とハーネス（`harness/main.swift`）、見た目を書き出す `preview.sh`（`preview/main.swift`） |

## 保存の仕組み

```text
~/Library/Application Support/CorkClip/
├── database/history.sqlite3   項目・型の一覧・タグの写し・全文検索（WAL）
├── blobs/ab/<sha256>.bin      生データ（中身のハッシュ名。同じデータは1つだけ）
├── thumbs/<項目ID>.png        一覧用のサムネ
└── settings.json              このMacの設定
```

- 1回のコピーは、`NSPasteboardItem` ごと・型ごとに `clip_representations` の1行になります。貼るときは同じ並びで `NSPasteboardItem` を作り直すので、アプリ独自の型（パワポの図形など）も元のまま戻ります。
- 全ての項目・型・データから作るハッシュ（`clips.content_hash`）で重複を判定し、同じ物は回数を増やして先頭に移します。定型文は重複を判定しません。
- 自分が書き戻した物には `io.github.kobito-tools.corkclip.own` の型を付け、監視側で取らないようにしています。
- 取得（クリップボードを読む）はメインスレッド、保存・整理・タグの同期・書き出しは裏の1本のキュー、文字認識は別のキューです。`ClipStore` の公開メソッドは1つのロックの中で動きます。
- 検索は FTS5 の trigram（3文字以上）と、それより短い語の部分一致を組み合わせます。タグの名前も対象です。
- 数式画像には元の式と描き方（`LatexSource` の JSON）を、自分の型・PNG の説明・PDF のキーワードの3か所に入れます。どれか1つが残っていれば、ほかのアプリから戻ってきても数式として扱えます。

## シリーズとのつながり

ほかのアプリとは、`docs/kobito-spec/CONTRACTS.md` の約束（データの形）だけでつながります。ほかのアプリの名前は、コード・画面・文書のどこにも書きません（「名指ししない規則」）。

```text
~/Library/Application Support/kobito-tools/   （KOBITO_CONFIG_DIR で変えられる）
├── apps/corkclip.json           ④ 起動情報。起動のたびに書く（open -b <バンドルID>、見せ方と操作。embed・receive は持たない）
├── apps/*.json                     ほかのアプリの起動情報。receive を集めて「送る」の送り先にする
└── datasets.json                   ⑥ 基準パスの履歴。基準パスの候補にし、開いたら自分の1件を書く

<基準パス>/.kobito-tools/
├── dataset.json                    ⓪-1 読むだけ（無ければ ID を尋ねて作る）
├── Tags/tags.json                  ⓪-2 共有タグ。このMacの履歴DBの tags・tag_categories はその写し
└── CorkClip/                    カードに残す（⌘S・自動で残すタグ）
    ├── lock.json                   書く間だけ置く使用中の印
    ├── database/kept.sqlite3       残したクリップの写し（schema/kept/・DELETE モード）
    ├── uploads/                    残した画像（PNG）
    └── cards.jsonl                 ③ 日ごとに1枚のカード

$TMPDIR/kobito-share/<UUID>.json    ⑦ 送る中身（KOBITO_SHARE_DIR で変えられる）
```

- **共有タグ**：起動時、基準パスを変えたとき、タグを付け外ししたときに、シリーズ共通の規則（`TagStore.swift`）で `tags.json` と統合します。
- **見せ方と操作**：`Series.swift` の `color`・`glyph`・`kinds`・`actions` に書きます。アイコン画像は `build.sh` が `.app` の `Resources/icon-256.png` に作り、起動情報にはその絶対パスを書きます（無ければ `glyph` だけ）。操作を足すときは、その URL を `Series.route` でも受け付け、テストの id の一覧も直します。
- **URL**：`kobito://corkclip/day/<日付>`・`kobito://corkclip/open/<ID>`（ほかに `panel`・`snippet`・`latex`・`settings`）は「URL を開く」Apple Event（`kAEGetURL`）で届きます。`applicationWillFinishLaunching` で受け口を作るので、未起動から開かれても届きます。`kobito` スキームは Info.plist に登録しません。
- **送る**：送り先は起動情報の `receive` から実行時に作ります。口が受け取れる種類（`accepts`）だけを入れて受け渡しファイルを書き、口の `url` の `{file}` を置き換えて、送り先の起動情報の `command` で開きます。
- **カードに残す**：残した物は基準パスの `kept.sqlite3` に写し（複数のMacで同じ基準パスを使えるように、このMacの履歴ではなく基準パスに置く）、そのたびに `cards.jsonl` を全件書き直します。以前の書き出し先（`database/corkclip.sqlite3` の日ごとのメモ）は、初めて開いたときに一度だけ写します（元のファイルは消しません）。
- **約束の確かめ**：`CorkClip.app/Contents/MacOS/CorkClip --write-launch-info` は起動情報だけを書いて終わります。`KOBITO_CONFIG_DIR` を一時フォルダに向けて実行し、書き出した JSON を `docs/kobito-spec/CONTRACTS.md` の④の形と見比べて確かめられます（起動情報とカードの形は `tests/run.sh` も確かめます）。
- **目印と名乗り**：リポジトリの直下の `kobito-app.json` は、シリーズの決まり（`docs/kobito-spec/APP_PACKAGE.md`）の目印です。`.app` で配るので `"kind": "native"` と書き、`launch.py` は持ちません（登録は今までどおり `setup.sh` と `--write-launch-info`）。アプリID・表示名・バンドルIDは `Series.swift`・`build.sh` とそろえます（`tests/run.sh` が確かめます）。`CorkClip --metadata` は、起動情報と同じ JSON を標準出力に出すだけで、何も書かず、何も起動しません。
