# アプリの入口と目印（launch.py と kobito-app.json）

> **状態：決定（2026-10-21）**。kobito-workspace は、この決まりのとおりに動きます（共通部品 `kit.cli`・`kit.manifest`、workspace の「見つかったアプリ」、`install.sh` の一覧）。各アプリをこの形にそろえるのは、これからです（§9）。

kobito シリーズのアプリが、みな**同じ入口**（`launch.py`）と**同じ目印**（`kobito-app.json`）を持つようにする決まりです。こうすると、新しいアプリが来ても、kobito-workspace と `install.sh` を直さずに済みます。

利用者の言葉：

> アプリごとに起動コマンドが『[アプリ名].py』となっていますが、『launch.py』で統一してしまった方が良さそう。（略）そうすれば kobito-workspace は新しいアプリが来ても何も変更しなくて良くなる。同じインタフェースでカプセル化するという観点では、発想はオブジェクト指向に近い。

## 1. 考え方

| 決まり | 内容 |
|---|---|
| 同じ形で呼べる | どのアプリも、同じ名前の入口を、同じ引数で呼べる。呼ぶ側（workspace・`setup.sh`・ランチャー）は、アプリの中身を知らなくてよい。オブジェクト指向で、同じインタフェースを持つクラスを、中身を知らずに呼ぶのと同じ |
| はっきり名乗る | 「`setup.sh` と `launch.py` がたまたまある」ではなく、目印のファイル `kobito-app.json` で「kobito シリーズのアプリです」と名乗る。ほかのフォルダを、まちがえてシリーズのアプリと思わない |
| 読むだけで分かる | 目印は JSON のファイルなので、読むだけで判定できる。見つけるために、何かを実行することはない |
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
  "app": "sample",
  "name": "Sample",
  "name_en": "Sample",
  "description": "説明のための架空のメモのアプリ",
  "description_en": "A made-up notes app for the examples",
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
| `setup` | | 初期設定のファイル名。書かなければ `"setup.sh"`。リポジトリの直下のファイルの名前だけ（`/` や `..` を含めない） |
| `contracts` | ○ | 対応する約束の版。今は `1` |
| `name_en` | | 英語の表示名 |
| `description`・`description_en` | | 一言の説明（`install.sh` の一覧に出す） |
| `repository` | | GitHub のリポジトリ（`owner/name`） |
| `bundle_id` | | `native` のアプリの、macOS のバンドルID |
| `platforms` | | 動く OS の配列（`macos`・`windows`・`linux`）。書かなければ分からない、とみなす |

- 必須の項目が欠けている・形が違う目印は、**まるごと捨てます**（そのフォルダは、シリーズのアプリとして扱わない）。
- 任意の項目は、形が違えば、その項目だけを捨てます。知らない項目は無視します。
- 大きさは 64 KB までにします。
- アイコン・色・操作などの見せ方は、目印には書きません。起動情報④（`--metadata`）で名乗ります（[APP_INTERFACE.md](APP_INTERFACE.md)）。目印は「誰か」を名乗るだけで、「どう見せるか」は④が受け持ちます。
- 目印の `app`・`name` と、`--metadata` の `app`・`name` は、同じにします。

## 3. 入口 `launch.py` の引数

Python のアプリの入口は、**リポジトリの直下の `launch.py` だけ**にします。`sample.py` のような、アプリの名前の入口は置きません。

| 起動の形 | すること |
|---|---|
| `launch.py` | 画面（単体のウインドウ）を開く |
| `launch.py --embedded --dataset <基準パス> --parent-origin <origin>` | workspace に埋め込む（約束④「workspace の中で表示するときの起動」と⑤）。ウインドウを開かず、`{"kobito":"ready","url":…}` を1行書く |
| `launch.py --write-launch-info` | 起動情報④を書いて、すぐ終わる。画面は開かない（`setup.sh` が使う） |
| `launch.py --metadata` | 名乗り（④と同じ形の JSON）を標準出力に出すだけ。何も書かず、何も起動しない |

- アプリ独自の引数や `kobito://…` の URL は、その後ろに続けてかまいません（例：`launch.py kobito://sample/new`）。
- 起動情報④の `command` は `["<uv>", "run", "--project", "<リポジトリ>", "<リポジトリ>/launch.py"]` に、`embed` は `["--embedded"]` にします。workspace は `<command> <embed> --dataset … --parent-origin …` で起動するので、上の表の形になります。
- 埋め込めないアプリ（workspace 自身など）は、`--embedded` を断ります（終了コード 2）。
- 画面を開くとき・埋め込むときも、先に起動情報④を書き直します（フォルダを移しても追いつくように）。書けなくても、起動は続けます。
- 終了コードは、0 が成功、1 が失敗（名乗りの形が違う・書けない）、2 が引数の誤りです。

共通部品の `kit.cli.run()` が、この引数を読んで、アプリが渡した関数を呼び分けます（§9 の見本、[KIT.md](KIT.md)）。

## 4. `--metadata` の出力

起動情報④と同じ形の JSON を、そのまま出します。

```json
{
  "app": "sample",
  "name": "Sample",
  "command": ["/Users/…/.local/bin/uv", "run", "--project", "/Users/…/Sample", "/Users/…/Sample/launch.py"],
  "embed": ["--embedded"],
  "icon": { "file": "/Users/…/Sample/assets/icon.svg", "glyph": "✎" },
  "actions": [ { "id": "new", "label": "新しいメモ", "url": "kobito://sample/new", "role": "new" } ]
}
```

- 項目の意味は [CONTRACTS.md](CONTRACTS.md) の ④ のとおりです。
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
| 規格の文書 | 共通部品を同梱しないので、規格の文書だけを写して持つ。kobito-workspace で `uv run scripts/vendor_kit.py --docs-only <リポジトリ>/docs/kobito-spec` を動かすと、`docs/kobito-spec/` に写る（`--check --docs-only` で、手で書き換えていないか・元より古いかを確かめられる） |

## 6. 見つけ方（kobito-workspace）

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

## 7. `install.sh` の一覧に出る条件

kobito-workspace の `install.sh` は、アプリの名前を持たず、GitHub から一覧を取り寄せます。アプリの側で守ることは次のとおりです（作り方の詳しい決まりは、kobito-workspace の `docs/INSTALL.md`）。

- organization `kobito-tools` の、公開のリポジトリであること。しまわれた（archived）リポジトリは出ません。
- topic `kobito-app` が付いていること。
- 既定のブランチの直下に、形の正しい `kobito-app.json` があること。表示名・説明・種類（Python かネイティブか）は、目印から出します。読めない・形が違うリポジトリは、一覧に入りません。
- クローンするフォルダの名前は、リポジトリ名です。

## 8. 利用者がすること（リポジトリを作るとき）

| すること | やり方 |
|---|---|
| リポジトリを公開にする | 認証なしの検索に出るのは、公開のリポジトリだけ |
| 直下に `kobito-app.json` を置き、既定のブランチ（`main`）へ入れる | `install.sh` は既定のブランチの目印を読む |
| topic `kobito-app` を付ける | GitHub のリポジトリの画面の右上「About」の ⚙ →「Topics」に `kobito-app` と入れて保存。または `gh repo edit kobito-tools/<リポジトリ名> --add-topic kobito-app` |
| シリーズでなくなったら | topic を外すか、リポジトリをしまう（archive） |

topic を付けてから検索に出るまで、数分かかることがあります。

## 9. 各アプリでやること

| # | すること |
|---|---|
| 1 | kobito-workspace で `uv run scripts/vendor_kit.py <アプリのパッケージ>` を動かし、共通部品を写し直す（`kit.cli`・`kit.manifest` と、規格の文書 `kobito_kit/docs/` が入る） |
| 2 | リポジトリの直下に `launch.py` を置き、`<アプリ名>.py` の入口を消す |
| 3 | 起動情報④の `command` を `cli.launch_command(<リポジトリ>)`（`launch.py` を指す）に、`embed` を `cli.EMBED` にする |
| 4 | リポジトリの直下に `kobito-app.json` を置く |
| 5 | `setup.sh` の起動情報の書き出しを `uv run launch.py --write-launch-info` に、起動のしかたの表示を `uv run launch.py` に直す。README の起動のしかたも直す |
| 6 | テストを足す：`--metadata` が④の形を出して何も書かないこと、目印の `app`・`name` と `--metadata` がそろっていること |

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

from .kobito_kit import cli, dataset, embed

APP = dataset.AppSpec(id="sample", name="Sample", directory="Sample", subdirectories=("database",))
REPOSITORY = Path(__file__).resolve().parents[1]


def metadata():
    """名乗り（起動情報④と同じ形）。何も書かず、何も起動しない。"""
    return {
        "app": APP.id, "name": APP.name,
        "command": cli.launch_command(REPOSITORY),  # uv run --project <リポジトリ> <リポジトリ>/launch.py
        "embed": cli.EMBED,                          # ["--embedded"]
        "icon": {"file": str(REPOSITORY / "assets" / "icon.svg"), "glyph": "S"},
        "actions": [{"id": "new", "label": "新しいメモ", "url": "kobito://sample/new", "role": "new"}],
    }


def open_window(options, rest):
    """単体のウインドウで開く。rest はアプリ独自の引数と kobito:// の URL。"""
    ...


def run_embedded(options, rest):
    """workspace に埋め込む。options.dataset・options.parent_origin を使い、embed.announce_ready(url) を呼ぶ。"""
    ...


def main(argv):
    return cli.run(argv, metadata=metadata, window=open_window, embedded=run_embedded)
```

kobito-workspace 自身も、この形です（`launch.py`・`kobito_workspace/app/main.py`。workspace は埋め込まれないので `embedded` を渡さない）。

### `kobito-app.json` の見本（ネイティブ）

```json
{ "format": "kobito-app", "v": 1, "app": "sample-native", "name": "Sample Native", "kind": "native", "setup": "setup.sh",
  "contracts": 1, "bundle_id": "…", "description": "説明のための架空の常駐アプリ", "repository": "kobito-tools/SampleNative", "platforms": ["macos"] }
```

## 10. 決まったこと（2026-10-21）

| 項目 | 決まったこと |
|---|---|
| 入口 | Python のアプリは、リポジトリの直下の `launch.py` だけ。引数の形は全アプリ同じ（§3） |
| 目印 | 各リポジトリの直下に `kobito-app.json`（§2）。読むだけで判定し、何も実行しない |
| 特別枠 | `.app` で配るアプリは `launch.py` を持たず、`"kind": "native"`。`.app` の `--write-launch-info` と `setup.sh` で登録する（§5） |
| 見つけ方 | 起動情報④が主。並びのフォルダから目印を探すのが補い。登録は利用者が OK したときだけ（§6） |
| install.sh | GitHub の topic `kobito-app` で一覧を作り、目印から表示名と種類を出す（§7） |
| アプリID | 一覧は持たない。各アプリが目印と④で名乗り、かぶったら登録させずに知らせる（2026-10-21 に追記。§6、[CONTRACTS.md「アプリID」](CONTRACTS.md#アプリid)） |
| 置き場所 | 約束①〜⑦には足さず、この文書に別の決まりとして置く（§1） |
