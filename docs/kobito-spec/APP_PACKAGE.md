# リポジトリの形（kobito-app.json・kobito/・launch.py・setup.sh）

> **状態：決定（2026-10-21）**。kobito-workspace は、この決まりのとおりに動きます（共通部品 `kit.package`・`kit.manifest`・`kit.cli`・`setup.zsh`・`kit.testing`、workspace の設定の「アプリ」と「見つかったアプリ」、`install.sh` の一覧、確かめの道具 `scripts/check_package.py`）。各アプリをこの形にそろえるのは、これからです（§11）。

kobito シリーズのどのリポジトリも、**同じ名前のファイルを、同じ場所に**置く決まりです。こうすると、並べる側（kobito-workspace・`install.sh`・organization のプロフィール）は、同じ場所にほかのアプリのリポジトリがあれば、中身を知らなくても読み込んで、紹介のカードやアイコンを出せます。新しいアプリが来ても、並べる側は直しません。

利用者の言葉：

> アプリごとに起動コマンドが『[アプリ名].py』となっていますが、『launch.py』で統一してしまった方が良さそう。（略）同じインタフェースでカプセル化するという観点では、発想はオブジェクト指向に近い。

> 他アプリの紹介カード・埋め込み・データ共有、その他アイコンなども含め、全て同じ名前のファイルと構造で規格化しておけば、同じパスに他のアプリが存在していれば自動的に読み込んで表示させるフレームワークができるはず。

## 0. リポジトリの形

```text
<アプリ>/
  kobito-app.json      名乗り（名前・説明・種類・版・規格の版・紹介のカードの中身）
  kobito/              外に見せる物を置く決まった場所
    icon.svg           アイコンの元（どのアプリも同じ名前）
    icon-1024.png      書き出したアイコン（1024×1024）
    screenshot.png     紹介のカードの画像（任意）
  launch.py            入口（Python のアプリ）。ネイティブのアプリは .app
  setup.sh             初期設定（共通の手順は setup.zsh を読み込む）
  Setup.command        Finder から開く入口（どのアプリも同じ名前）
  README.md  LICENSE
  docs/  scripts/  tests/
```

| ファイル | Python | ネイティブ | 内容 |
|---|---|---|---|
| `kobito-app.json` | 必須 | 必須 | 名乗り（§2）。紹介のカードの文字はここから作る |
| `kobito/icon.svg` | 必須 | 必須 | アイコンの元。`viewBox` を持つ SVG、256 KB まで、`script` を含めない |
| `kobito/icon-1024.png` | 必須 | 必須 | `icon.svg` から書き出した 1024×1024 の PNG、2 MB まで |
| `kobito/screenshot.png` | 任意 | 任意 | 紹介のカードの画像。PNG、2 MB まで。横長（たとえば 1280×800）がよい |
| `launch.py` | 必須 | — | ただ1つの入口（§3）。ネイティブのアプリは `.app` で配る（§5） |
| `pyproject.toml` | 必須 | — | `[project].version` は目印の `version` とそろえる |
| `setup.sh` | 必須 | 必須 | 初期設定（[SETUP.md](SETUP.md)）。git で実行できる設定（100755） |
| `Setup.command` | 必須 | 必須 | `setup.sh` を Finder から動かす入口。git で実行できる設定（100755）。`<アプリ名>-Setup.command` はやめる |
| `README.md`・`LICENSE` | 必須 | 必須 | 公開のリポジトリなので置く |
| `tests/test_*.py` | 必須 | 任意 | テスト（§10）。ネイティブのアプリは、自分の言語のやり方でよい |
| `docs/` | 任意 | 任意 | 設計などの文書。ネイティブのアプリは、規格の写しを `docs/kobito-spec/` に置く |
| `scripts/` | 任意 | 任意 | 開発用の道具。画面を確かめる起動は `launch.py --dev` を使い、`scripts/dev_server.py` は置かない |
| 共通部品の写し | `<パッケージ>/kobito_kit/` | `docs/kobito-spec/`（文書と `setup.zsh`） | `vendor_kit.py` で写す。手で書き換えない |

- `kobito/` には、上の決まった名前のファイルだけを置きます。画像のパスは、目印にも起動情報にも書きません（決まった名前で探す）。
- 外から読んでよいのは、**`kobito-app.json` と `kobito/` と、`launch.py` の決まった引数だけ**です。並べる側は、リポジトリのほかのファイル（アプリのパッケージ・設定・データ）を読みません。オブジェクト指向で、公開のインタフェースだけを使い、中身に触らないのと同じです。
- 形を守っているかは、kobito-workspace で `uv run scripts/check_package.py <リポジトリ>` を動かすと分かります（§12）。

## 1. 考え方

| 決まり | 内容 |
|---|---|
| 同じ形で呼べる | どのアプリも、同じ名前の入口を、同じ引数で呼べる。呼ぶ側（workspace・`setup.sh`・ランチャー）は、アプリの中身を知らなくてよい。オブジェクト指向で、同じインタフェースを持つクラスを、中身を知らずに呼ぶのと同じ |
| はっきり名乗る | 「`setup.sh` と `launch.py` がたまたまある」ではなく、目印のファイル `kobito-app.json` で「kobito シリーズのアプリです」と名乗る。ほかのフォルダを、まちがえてシリーズのアプリと思わない |
| 読むだけで分かる | 目印は JSON のファイルなので、読むだけで判定できる。見つけるために、何かを実行することはない |
| 紹介のカードはデータ | 紹介のカードは、目印と `kobito/` の画像だけから作る。スクリプトを動かさないので安全で、workspace・`install.sh`・organization のプロフィールが同じデータを使い回せる（§6） |
| 動かすのは、利用者が OK したときだけ | 見つけたフォルダの `setup.sh`・`launch.py` は、利用者が OK するまで動かさない |
| 約束 v1 は変えない | 起動情報④の形も意味も、そのまま。`launch.py --metadata` が出すのは、④と同じ形の JSON |

### 約束（CONTRACTS.md）との関係

この決まりは、[CONTRACTS.md](CONTRACTS.md) の約束①〜⑦には足さず、**別の決まり**として、この文書に置きます。

- 約束①〜⑦は、動いているアプリどうしが受け渡す**データの形**です。永久に変えず、版 `v` も上げません。
- 入口と目印は、アプリを**どう配り、どう見つけ、どう起動するか**の決まりです。リポジトリの作りに近く、これから増える項目もありそうです。目印の版（`v`）を、約束とは別に持てるようにしておきます。
- 起動情報④とは、`--metadata` の出力が④と同じ形、という所でだけつながります。④の項目の意味は変えません。

## 2. 目印 `kobito-app.json`

各アプリの**リポジトリの直下**に置きます。

```json
{
  "format": "kobito-app",
  "v": 1,
  "package": 1,
  "app": "sample",
  "name": "Sample",
  "name_en": "Sample",
  "tagline": "思いついたことを、すぐ書きとめる",
  "tagline_en": "Jot things down the moment they come",
  "description": "説明のための架空のメモのアプリ",
  "description_en": "A made-up notes app for the examples",
  "version": "0.1.0",
  "kind": "python",
  "entry": "launch.py",
  "setup": "setup.sh",
  "contracts": 1,
  "repository": "kobito-tools/Sample",
  "platforms": ["macos"]
}
```

| 項目 | 必須 | 内容 |
|---|---|---|
| `format` | ○ | いつも `"kobito-app"`。これで「kobito シリーズの目印」と分かる |
| `v` | ○ | 目印の版。今は `1`。読む側は、知らない版の目印を捨てる |
| `app` | ○ | アプリID（[CONTRACTS.md「アプリID」](CONTRACTS.md#アプリid)）。英小文字で始まり、英小文字・数字・`-` で40文字まで。ほかのアプリとかぶらないものを、自分で選ぶ |
| `name` | ○ | 表示名 |
| `kind` | ○ | `"python"`（`launch.py` で起動する）か `"native"`（`.app` などで配る。§5） |
| `entry` | `python` のとき | 入口。いつも `"launch.py"`。書かなければ `"launch.py"` とみなす。`native` のアプリは書かない（書いても読む側は使わない） |
| `setup` | | 初期設定のファイル名。書かなければ `"setup.sh"`。リポジトリの直下のファイルの名前だけ（`/` や `..` を含めない）。リポジトリの形（§0）では `setup.sh` に決まっているので、書かないか `"setup.sh"` にする |
| `contracts` | ○ | 対応する約束の版。今は `1` |
| `name_en` | | 英語の表示名 |
| `description`・`description_en` | | 一言の説明（`install.sh` の一覧に出す） |
| `repository` | | GitHub のリポジトリ（`owner/name`） |
| `bundle_id` | | `native` のアプリの、macOS のバンドルID |
| `package` | （○） | リポジトリの形（この文書の §0）の版。今は `1` |
| `version` | （○） | アプリの版（`1.0.0` のような形）。Python のアプリは `pyproject.toml` の版とそろえる |
| `tagline`・`tagline_en` | （○）・ | 紹介のカードのひとこと。1行、80文字まで。`tagline` が無ければ `description` を使う |
| `platforms` | | 動く OS の配列（`macos`・`windows`・`linux`）。書かなければ分からない、とみなす |

- （○）の項目は、読む側（workspace・`install.sh`）では任意ですが、リポジトリの形としては必須です。`check_package.py` が確かめます。前からある目印も読めるよう、読む側は無くても捨てません。
- 必須の項目が欠けている・形が違う目印は、**まるごと捨てます**（そのフォルダは、シリーズのアプリとして扱わない）。
- 任意の項目は、形が違えば、その項目だけを捨てます。知らない項目は無視します。
- 大きさは 64 KB までにします。
- 画像（アイコン・紹介のカードの画像）のパスは、目印に書きません。`kobito/` の決まった名前のものを使います。
- 色・種類・操作などの、動いているアプリの見せ方は、起動情報④（`--metadata`）で名乗ります（[APP_INTERFACE.md](APP_INTERFACE.md)）。目印は「誰か」と紹介のカードを、④は「動いているときにどう見せるか」を受け持ちます。
- 目印の `app`・`name` と、`--metadata` の `app`・`name` は、同じにします。

## 3. 入口 `launch.py` の引数

Python のアプリの入口は、**リポジトリの直下の `launch.py` だけ**にします。`sample.py` のような、アプリの名前の入口は置きません。

| 起動の形 | すること |
|---|---|
| `launch.py` | 画面（単体のウインドウ）を開く |
| `launch.py --embedded --dataset <基準パス> --parent-origin <origin>` | workspace に埋め込む（約束④「workspace の中で表示するときの起動」と⑤）。ウインドウを開かず、`{"kobito":"ready","url":…}` を1行書く |
| `launch.py --write-launch-info` | 起動情報④を書いて、すぐ終わる。画面は開かない（`setup.sh` が使う） |
| `launch.py --metadata` | 名乗り（④と同じ形の JSON）を標準出力に出すだけ。何も書かず、何も起動しない |
| `launch.py --dev [--dataset <基準パス>] [--port <ポート>]` | 開発用。ウインドウを開かずにサーバーだけを動かし、ブラウザで開く URL を1行出す。Ctrl-C で止まる。起動情報は書かない |

- アプリ独自の引数や `kobito://…` の URL は、その後ろに続けてかまいません（例：`launch.py kobito://sample/new`）。
- 起動情報④の `command` は `["<uv>", "run", "--project", "<リポジトリ>", "<リポジトリ>/launch.py"]` に、`embed` は `["--embedded"]` にします。workspace は `<command> <embed> --dataset … --parent-origin …` で起動するので、上の表の形になります。
- 埋め込めないアプリ（workspace 自身など）は、`--embedded` を断ります（終了コード 2）。
- 画面を開くとき・埋め込むときも、先に起動情報④を書き直します（フォルダを移しても追いつくように）。書けなくても、起動は続けます。
- 終了コードは、0 が成功、1 が失敗（名乗りの形が違う・書けない）、2 が引数の誤りです。`--dev` を持たないアプリは、`--dev` を断ります（終了コード 2）。
- `--dev` では、ファイルを選ぶダイアログとドロップは使えません（ウインドウが無いため）。実際の設定に触れずに試すときは、`KOBITO_CONFIG_DIR` を一時フォルダに向けて動かします。

共通部品の `kit.cli.run()` が、この引数を読んで、アプリが渡した関数を呼び分けます（§11 の見本、[KIT.md](KIT.md)）。

## 4. `--metadata` の出力

起動情報④と同じ形の JSON を、そのまま出します。

```json
{
  "app": "sample",
  "name": "Sample",
  "command": ["/Users/…/.local/bin/uv", "run", "--project", "/Users/…/Sample", "/Users/…/Sample/launch.py"],
  "embed": ["--embedded"],
  "icon": { "file": "/Users/…/Sample/kobito/icon.svg", "glyph": "✎" },
  "actions": [ { "id": "new", "label": "新しいメモ", "url": "kobito://sample/new", "role": "new" } ]
}
```

- 項目の意味は [CONTRACTS.md](CONTRACTS.md) の ④ のとおりです。
- `icon.file` は、いつも `<リポジトリ>/kobito/icon.svg` を指します（`package.icon_record(<リポジトリ>, <1文字>)` で作る）。
- `--write-launch-info` は、これと同じものを `kobito-tools/apps/<アプリID>.json` に書きます。
- 形が④と合わなければ、何も出さずに終了コード 1 で終わります。

## 5. ネイティブのアプリ（特別枠）

Swift・Tauri などで作り、アプリの形（`.app`）で配るアプリは、`launch.py` を持ちません。

| 項目 | 内容 |
|---|---|
| 目印 | `kobito-app.json` に `"kind": "native"` と書く。`entry` は書かない。`bundle_id` を書いてよい |
| 登録 | `setup.sh` がビルドし、`.app` の `--write-launch-info` で起動情報④を書く（[SETUP.md](SETUP.md)） |
| 起動 | 起動情報④の `command`（`["/usr/bin/open", "-b", "<バンドルID>"]` など）。今までどおり |
| `--metadata` | `.app` の実行ファイルが同じ引数を受け付けると、そろって見やすい（任意） |
| 規格の文書 | 共通部品を同梱しないので、規格の文書と `setup.zsh` だけを写して持つ。kobito-workspace で `uv run scripts/vendor_kit.py --docs-only <リポジトリ>/docs/kobito-spec` を動かすと、`docs/kobito-spec/` に写る（`--check --docs-only` で、手で書き換えていないか・元より古いかを確かめられる） |
| `setup.sh` | `docs/kobito-spec/setup.zsh` を読み込み、自分の手順（ビルドなど）を足す（[SETUP.md](SETUP.md)） |
| アイコン | Python のアプリと同じく `kobito/icon.svg`・`kobito/icon-1024.png`。`.app` のアイコン（`.icns`）は、ここから作る |
| テスト | 自分の言語のやり方でよい（`swift test`・`cargo test` など） |

## 6. 紹介のカード

紹介のカードは、アプリを紹介する小さな札です。**目印と `kobito/` の画像だけから作り、スクリプトは動かしません。** 入っていないアプリ・まだ登録していないアプリも、同じ形で紹介できます。

| カードの部分 | どこから | 無いとき |
|---|---|---|
| アイコン | `kobito/icon.svg`（無ければ `kobito/icon-1024.png`） | 起動情報④の見せ方か、名前の1文字目 |
| 名前 | 目印の `name`（英語の画面では `name_en`） | — |
| ひとこと | 目印の `tagline`（英語の画面では `tagline_en`） | `description`、それも無ければ出さない |
| 種類 | 目印の `kind`（Python・ネイティブ） | — |
| 画像 | `kobito/screenshot.png` | 出さない |
| 版・リポジトリ | 目印の `version`・`repository` | 出さない |

- 共通部品の `kit.package.AppPackage(<フォルダ>).card()` が、この形の辞書を返します（画像は、あればリポジトリの中の決まった名前、無ければ `None`）。
- 使う所：kobito-workspace の設定の「アプリ」と「見つかったアプリ」、`install.sh` の一覧（文字だけ：名前・ひとこと・種類）、organization のプロフィール（別のリポジトリ。あとで同じ項目にそろえる）。
- workspace は画像を `/api/discovery/image?folder=…&name=icon|screenshot` で配ります。今探して見つかるフォルダの、決まった名前のファイルだけを読みます。フォルダの外を指すファイル（シンボリックリンクなど）と、大きすぎるファイルは使いません。

## 7. 見つけ方（kobito-workspace）

| 順 | 見つけ方 | 内容 |
|---|---|---|
| 主 | 起動情報④ | PC 固有領域の `kobito-tools/apps/*.json`。`.app` も、どこに置いたアプリも見つかる。workspace に並べるのは、ここに登録されたアプリだけ |
| 補 | フォルダから探す | 並びのフォルダ（kobito-workspace の親のフォルダ）と、設定で足したフォルダの、**直下のフォルダ**を見て、`kobito-app.json` があるものを探す |

- フォルダから探すときは、目印を読むだけで、何も実行しません。隠しフォルダ（`.` で始まる）は見ません。
- 見つかって、まだ④に登録されていないアプリは、設定の画面の「見つかったアプリ」に出します。
- 利用者が「登録する…」を押し、動かすコマンドを見て「動かす」を押したときだけ、そのアプリのフォルダで次を動かします。
  - `setup.sh` があれば `zsh <フォルダ>/setup.sh --yes`（端末が無いので、尋ねる場面では既定の答えを選ぶ）
  - `setup.sh` が無い Python のアプリは `<uv> run --project <フォルダ> <フォルダ>/launch.py --write-launch-info`
- 動かすのは、その時点で探し直して見つかったフォルダの、目印が名乗ったファイルだけです。フォルダの外を指すファイル（シンボリックリンクなど）は動かしません。
- 登録の記録は `kobito-tools/Workspace/logs/setup-<アプリID>.log` に残します。終わったら、④が書かれたかを確かめます。
- 探すフォルダは、設定の「アプリを探すフォルダ」で足したり外したりできます（並びのフォルダは外せません）。
- 同じアプリIDの目印が2つ以上見つかったとき、または別の場所のアプリが同じ ID ですでに④に登録されているときは、登録させずに知らせます（[CONTRACTS.md「ID がかぶったとき」](CONTRACTS.md#id-がかぶったとき)）。

## 8. `install.sh` の一覧に出る条件

kobito-workspace の `install.sh` は、アプリの名前を持たず、GitHub から一覧を取り寄せます。アプリの側で守ることは次のとおりです（作り方の詳しい決まりは、kobito-workspace の `docs/INSTALL.md`）。

- organization `kobito-tools` の、公開のリポジトリであること。しまわれた（archived）リポジトリは出ません。
- topic `kobito-app` が付いていること。
- 既定のブランチの直下に、形の正しい `kobito-app.json` があること。表示名・ひとこと（無ければ説明）・種類（Python かネイティブか）は、目印から出します（§6 の紹介のカードと同じ項目）。読めない・形が違うリポジトリは、一覧に入りません。
- クローンするフォルダの名前は、リポジトリ名です。

## 9. 利用者がすること（リポジトリを作るとき）

| すること | やり方 |
|---|---|
| リポジトリを公開にする | 認証なしの検索に出るのは、公開のリポジトリだけ |
| 直下に `kobito-app.json` を置き、既定のブランチ（`main`）へ入れる | `install.sh` は既定のブランチの目印を読む |
| topic `kobito-app` を付ける | GitHub のリポジトリの画面の右上「About」の ⚙ →「Topics」に `kobito-app` と入れて保存。または `gh repo edit kobito-tools/<リポジトリ名> --add-topic kobito-app` |
| シリーズでなくなったら | topic を外すか、リポジトリをしまう（archive） |

topic を付けてから検索に出るまで、数分かかることがあります。

## 10. テスト

どのアプリも、リポジトリの直下で、次の1行で全部のテストを動かします。

```bash
uv run python -m unittest discover -s tests -t tests
```

| 決まり | 内容 |
|---|---|
| 置き場所 | `tests/test_*.py`。共通の部分は `tests/helpers.py` に置き、`from helpers import …` で読む（`-t tests` なので、`tests/` が import の起点になる） |
| 実際の設定に触れない | `kit.testing.IsolatedTestCase` を土台にする。PC 固有領域（`KOBITO_CONFIG_DIR`）・受け渡しフォルダ（`KOBITO_SHARE_DIR`）・`HOME` を、テストごとの一時フォルダに向け、終わったら元に戻して消す |
| 外の道具が要るテスト | 道具が無ければ飛ばす（`unittest.skipUnless`）。別の1行を要らないようにする |
| ネイティブのアプリ | 自分の言語のやり方でよい（`swift test`・`cargo test` など）。README に書く |

```python
# tests/helpers.py
from sample_app.kobito_kit.testing import IsolatedTestCase


class TemporaryTestCase(IsolatedTestCase):
    """self.work（一時フォルダ）・self.config・self.share・self.home・self.base が使える。"""
```

## 11. 各アプリでやること

| # | すること |
|---|---|
| 1 | kobito-workspace で `uv run scripts/vendor_kit.py <アプリのパッケージ>` を動かし、共通部品 0.5.0 を写し直す（ネイティブのアプリは `--docs-only <リポジトリ>/docs/kobito-spec`） |
| 2 | `kobito/` を作り、アイコンを `kobito/icon.svg`・`kobito/icon-1024.png` に移す（`assets/icon.svg`・`web/icon.svg` などから）。紹介のカードの画像があれば `kobito/screenshot.png` |
| 3 | 起動情報④の `icon` を `package.icon_record(<リポジトリ>, <1文字>)` にする |
| 4 | `kobito-app.json` に `package: 1`・`version`・`tagline`・`tagline_en` を足す |
| 5 | `<アプリ名>-Setup.command` を `git mv` で `Setup.command` にする（100755 のまま） |
| 6 | `setup.sh` を、`setup.zsh` を読み込む短い形にする（[SETUP.md](SETUP.md) の見本）。自分だけの手順（常駐の登録など）は残す |
| 7 | `scripts/dev_server.py` をやめ、`cli.run(…, dev=…)` に開発用の起動を渡す（`launch.py --dev`） |
| 8 | テストを `tests/test_*.py` にそろえ、`uv run python -m unittest discover -s tests -t tests` で全部動くようにする。土台は `kit.testing.IsolatedTestCase` |
| 9 | README の起動・テストのしかたを直す |
| 10 | kobito-workspace で `uv run scripts/check_package.py <リポジトリ>` を動かし、守れていない所が無くなるまで直す |

### `launch.py` の見本

`launch.py`（リポジトリの直下）は、アプリの `main()` を呼ぶだけにします。

```python
"""Sample の入口（kobito シリーズの決まり：sample_app/kobito_kit/docs/APP_PACKAGE.md）。"""

import sys

from sample_app.main import main

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

`sample_app/main.py` が、名乗り・画面を開く・埋め込むの3つを `cli.run()` に渡します。

```python
from pathlib import Path

from .kobito_kit import cli, dataset, embed, package

APP = dataset.AppSpec(id="sample", name="Sample", directory="Sample", subdirectories=("database",))
REPOSITORY = Path(__file__).resolve().parents[1]


def metadata():
    """名乗り（起動情報④と同じ形）。何も書かず、何も起動しない。"""
    return {
        "app": APP.id, "name": APP.name,
        "command": cli.launch_command(REPOSITORY),  # uv run --project <リポジトリ> <リポジトリ>/launch.py
        "embed": cli.EMBED,                          # ["--embedded"]
        "icon": package.icon_record(REPOSITORY, "S"),  # <リポジトリ>/kobito/icon.svg
        "actions": [{"id": "new", "label": "新しいメモ", "url": "kobito://sample/new", "role": "new"}],
    }


def open_window(options, rest):
    """単体のウインドウで開く。rest はアプリ独自の引数と kobito:// の URL。"""
    ...


def run_embedded(options, rest):
    """workspace に埋め込む。options.dataset・options.parent_origin を使い、embed.announce_ready(url) を呼ぶ。"""
    ...


def serve_dev(options, rest):
    """開発用（--dev）。サーバーを動かして返す。片付けが要るなら (サーバー, 片付ける関数) を返す。"""
    ...


def main(argv):
    return cli.run(argv, metadata=metadata, window=open_window, embedded=run_embedded, dev=serve_dev)
```

kobito-workspace 自身も、この形です（`launch.py`・`kobito_workspace/app/main.py`。workspace は埋め込まれないので `embedded` を渡さない）。

### `kobito-app.json` の見本（ネイティブ）

```json
{ "format": "kobito-app", "v": 1, "package": 1, "app": "sample-native", "name": "Sample Native", "kind": "native", "contracts": 1,
  "version": "1.0.0", "tagline": "説明のための架空の常駐アプリ", "bundle_id": "…", "repository": "kobito-tools/SampleNative", "platforms": ["macos"] }
```


## 12. 確かめの道具 `check_package.py`

kobito-workspace で動かします。リポジトリがこの形を守っているかを調べ、守れていない所を一覧で出します。Python のアプリにも、ネイティブのアプリにも使えます。

```bash
uv run scripts/check_package.py ../Sample                 # 調べる（守れていれば終了コード 0、無ければ 1）
uv run scripts/check_package.py ../Sample ../SampleNative # いくつでも
uv run scripts/check_package.py --no-run ../Sample        # ファイルを読むだけ（setup.sh・launch.py を動かさない）
uv run scripts/check_package.py --json ../Sample          # 結果を JSON で
```

| 調べること | 内容 |
|---|---|
| 必須のファイル | §0 の表の「必須」がそろっているか。古い `<アプリ名>-Setup.command` が残っていないか |
| `kobito-app.json` | 形が正しいか。`package`・`version`・`tagline` があるか。画像のパスを書いていないか。`version` が `pyproject.toml` とそろっているか |
| `kobito/` | `icon.svg` が `viewBox` を持つ SVG で、`script` を含まず 256 KB までか。`icon-1024.png` が 1024×1024 の PNG か。`screenshot.png` が PNG か。決まっていないファイルが無いか |
| 実行できる設定 | `Setup.command`・`setup.sh` が git で 100755 か |
| 共通部品の写し | `<パッケージ>/kobito_kit/`（ネイティブのアプリは `docs/kobito-spec/`）が、元と同じか（手で書き換えていないか・古くないか） |
| テスト | Python のアプリに `tests/test_*.py` があるか |
| `setup.sh` を動かす | `--help` が使い方を出して 0、知らない引数で 2、`--dry-run --yes` が 0 で終わり、何も書かないか |
| `launch.py --metadata` を動かす | 何も書かずに、④の形の名乗りを出すか。`app`・`name` が目印とそろっているか。`command` がこのリポジトリの `launch.py`、`icon.file` が `kobito/icon.svg` を指すか |

- 利用者が自分のリポジトリに対して使う道具なので、`--no-run` でなければ、そのリポジトリの `setup.sh`・`launch.py` を動かします。動かすときは、PC 固有領域・受け渡しフォルダ・`HOME` を一時フォルダに向けます。
- workspace と `install.sh` は、ほかのアプリを並べるときに、この道具を使いません（並べる側は読むだけ）。

## 13. 決まったこと（2026-10-21）

| 項目 | 決まったこと |
|---|---|
| 入口 | Python のアプリは、リポジトリの直下の `launch.py` だけ。引数の形は全アプリ同じ（§3） |
| 目印 | 各リポジトリの直下に `kobito-app.json`（§2）。読むだけで判定し、何も実行しない |
| 特別枠 | `.app` で配るアプリは `launch.py` を持たず、`"kind": "native"`。`.app` の `--write-launch-info` と `setup.sh` で登録する（§5） |
| 見つけ方 | 起動情報④が主。並びのフォルダから目印を探すのが補い。登録は利用者が OK したときだけ（§7） |
| install.sh | GitHub の topic `kobito-app` で一覧を作り、目印から表示名・ひとこと・種類を出す（§8） |
| アプリID | 一覧は持たない。各アプリが目印と④で名乗り、かぶったら登録させずに知らせる（2026-10-21 に追記。§7、[CONTRACTS.md「アプリID」](CONTRACTS.md#アプリid)） |
| 置き場所 | 約束①〜⑦には足さず、この文書に別の決まりとして置く（§1） |
| リポジトリの形 | どのリポジトリも同じ名前のファイルと構造にする。外から読んでよいのは `kobito-app.json`・`kobito/`・`launch.py` の決まった引数だけ（2026-10-21 に追記。§0） |
| 紹介のカード | 目印と `kobito/` の画像だけから作り、スクリプトを動かさない。画像のパスは書かない（§6） |
| 共通の手順 | `setup.sh` の共通の手順は `setup.zsh`、開発用の起動は `launch.py --dev`、テストは `uv run python -m unittest discover -s tests -t tests` の1行（§3・§10、[SETUP.md](SETUP.md)） |
| 確かめ方 | `scripts/check_package.py <リポジトリ>`（§12） |
