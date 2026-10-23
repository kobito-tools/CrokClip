# 共通部品（kobito_kit）の使い方

kobito シリーズの Python アプリが同梱する共通部品の手引きです。元は kobito-workspace の `kobito_workspace/kit` にあります。部品は標準ライブラリだけで動きます。約束そのもの（データの形）は [CONTRACTS.md](CONTRACTS.md) にあり、ここに書くのはその読み書きの使い方です。

シリーズの規格の文書（この文書・[CONTRACTS.md](CONTRACTS.md)・[APP_PACKAGE.md](APP_PACKAGE.md)・[APP_INTERFACE.md](APP_INTERFACE.md)・[SETUP.md](SETUP.md)・[BRANCHING.md](BRANCHING.md)）は、共通部品の `docs/` にあり、写しと一緒に各アプリへ届きます。アプリの中では `<アプリのパッケージ>/kobito_kit/docs/` を見てください。

## 同梱のしかた

共通部品は依存として取り込まず、写しをアプリのパッケージの中に `kobito_kit/` として置きます（kobito-workspace の `docs/ARCHITECTURE.md`「各アプリへの同梱」）。

```bash
cd kobito-workspace
uv run scripts/vendor_kit.py ../Sample/sample_app          # 写す（既にある写しは置き換える）
uv run scripts/vendor_kit.py --check ../Sample/sample_app  # 手で書き換えていないか・元より古いか
```

共通部品を使わないアプリ（Swift・Tauri など）は、規格の文書だけを写します。写す先は、リポジトリの `docs/kobito-spec/` にします。

```bash
uv run scripts/vendor_kit.py --docs-only ../SampleNative/docs/kobito-spec          # 規格の文書だけを写す
uv run scripts/vendor_kit.py --check --docs-only ../SampleNative/docs/kobito-spec  # 同じく確かめる
```

- アプリのコードからは、`from .kobito_kit import dataset` のように、自分のパッケージの中のものとして使います。
- この文書の `kit.dataset` などは、アプリの中では `<アプリのパッケージ>.kobito_kit.dataset` のことです。
- 写しは直接書き換えません。直すときは kobito-workspace の `kobito_workspace/kit` を直し、テストを通してから写し直します。
- 写しにはテストを含みません。テストは kobito-workspace で実行します。
- 写しの `docs/` も書き換えません。規格を変えたいときは、kobito-workspace の `kobito_workspace/kit/docs/` を直します。

## モジュール

| モジュール | 主なもの | 内容 |
|---|---|---|
| `kit.dataset` | `AppSpec`・`read`・`create`・`base_path_for`・`DatasetLock`・`SharedDatasetLock`・`shared_settings`・`timestamp`・`local_timestamp` | 基準パス（⓪-1）とロック。`SharedDatasetLock` は、同じPCの同じアプリの複数のプロセス（画面と常駐など）でロックを分け合う |
| `kit.tags` | `TABLES_SQL`・`sync(database, base_path)` | 共有タグ（⓪-2）の同期 |
| `kit.database` | `Database`・`migrate(database, schema_directory, timestamp)` | SQLite（DELETE モード）と DB 更新 |
| `kit.contracts.files` | `make_ref`・`resolve`・`refind`・`valid_ref` | ① ファイル参照 |
| `kit.contracts.links` | `make`・`valid`・`app_of`・`can_open`・`open_link` | ② リンク |
| `kit.contracts.cards` | `make`・`write`・`read_all`・`valid` | ③ カード |
| `kit.contracts.launch` | `write`・`write_record`・`read`・`read_all`・`receive_targets`・`problems`・`actions`・`find_action`・`action_for_role`・`kind_order`・`dates_of`・`icon_file`・`COLORS` | ④ 起動情報と受け渡しの口、見せ方と操作（`name_en`・`icon`・`color`・`kinds`・`actions`） |
| `kit.contracts.history` | `record`・`candidates` | ⑥ 基準パスの履歴 |
| `kit.contracts.share` | `make`・`send`・`read`・`kinds_of` | ⑦ 受け渡しファイル |
| `kit.embed` | `parse_args`・`announce_ready`・`exit_when_parent_closes` | workspace の中での起動 |
| `kit.cli` | `run`・`launch_command`・`write_launch_info`・`EMBED`・`DevOptions` | 入口 `launch.py` の引数（`--metadata`・`--write-launch-info`・`--embedded …`・`--dev`）を読み、アプリが渡した「名乗りを作る」「画面を開く」「埋め込む」「開発用に動かす」を呼び分ける（[APP_PACKAGE.md](APP_PACKAGE.md)） |
| `kit.package` | `AppPackage`・`icon_record`・`ICON`・`ICON_PNG`・`SCREENSHOT` | リポジトリの形（[APP_PACKAGE.md §0](APP_PACKAGE.md)）。`AppPackage(<フォルダ>, <目印>)`・`AppPackage.read(<フォルダ>)`・`AppPackage.find([<フォルダ>…])` で読み、`.icon`・`.screenshot`・`.card()`（紹介のカード）を返す。`icon_record(<リポジトリ>, <1文字>)` は ④ の `icon`（`kobito/icon.svg`）。読むだけで、何も実行しない |
| `kit.testing` | `IsolatedTestCase` | テストの土台。`KOBITO_CONFIG_DIR`・`KOBITO_SHARE_DIR`・`HOME` を一時フォルダに向ける（[APP_PACKAGE.md §10](APP_PACKAGE.md)） |
| `setup.zsh` | `kobito_setup`・`kobito_python_app`・`kobito_ask`・`kobito_run`・`kobito_finish` など | `setup.sh` が読み込む共通の手順（zsh。[SETUP.md §3](SETUP.md)） |
| `kit.manifest` | `read`・`normalize`・`find`・`file_in`・`conflicts`・`conflict_message`・`FILE` | 目印 `kobito-app.json` を読んで確かめる（紹介のカードの `tagline`・`tagline_en`、`version`・`package` も）。フォルダの直下から目印のあるアプリを探す。アプリIDのかぶりを見つける（[CONTRACTS.md「ID がかぶったとき」](CONTRACTS.md#id-がかぶったとき)）。読むだけで、何も実行しない |
| `kit.server` | `PageServer`・`Request`・`Response` | ローカル HTTP サーバーの土台、共通の API、SSE。Server ヘッダーはアプリID（`kobito-<アプリID>`）なので、表示名は日本語でもよい |
| `kit.web/kobito-bridge.js` | `window.kobito` | 画面用。単体起動と埋め込みの違いを吸収し、⑤ を送受信する |
| `kit.llm` | `chat_json`・`load_config`・`save_config`・`LlmError` | ローカルLLM（OpenAI 互換 API、このPCのものだけ） |
| `kit.paths` | `series_directory`・`app_directory`・`Settings`・`write_json_atomic` | PC 固有領域（`kobito-tools/<App>/`） |
| `kit.popup` | `install_accessory`・`check_accessory`・`show`・`hide`・`keep_open` | 常駐プロセスや埋め込みのプロセスから、フォーカスを奪わない小さなウインドウを出す（pywebview 6.2.1 で確認。使うアプリは版を固定する） |
| `kit.lifecycle` | `on_terminate`・`wake_python_regularly` | macOS で pywebview の画面を出している間も、SIGTERM で終われるようにする |
| `kit.web/kobito-theme.css` | `--kobito-*` の CSS 変数 | シリーズ共通の配色（`/kobito/kobito-theme.css` で配る。ライト・ナイトは OS に合わせる）。アプリの色は `--kobito-app-<名前>`（8色）。色の地に乗せる文字は、白ではなく `--kobito-on-accent`・`--kobito-on-warn`・`--kobito-on-ok`・`--kobito-on-app`（ナイトでは暗い色。どの組み合わせもコントラスト比 4.5:1 以上） |

i18n（日本語で組み立て、表示直前に英語へ置き換える仕組み）は、まだありません。



## アプリの入口の形

入口は、リポジトリの直下の `launch.py` だけです（[APP_PACKAGE.md](APP_PACKAGE.md)）。`launch.py` はアプリの `main()` を呼ぶだけにし、`main()` は `cli.run()` に3つの関数を渡します。

```python
# launch.py（リポジトリの直下）
import sys

from sample_app.main import main

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

```python
# sample_app/main.py（kobito_kit は sample_app/kobito_kit/ に同梱した写し）
import threading
from pathlib import Path

from .kobito_kit import cli, dataset, embed, package, paths
from .kobito_kit.contracts import history
from .kobito_kit.server import PageServer

APP = dataset.AppSpec(id="sample", name="Sample", directory="Sample", subdirectories=("database",))
HERE = Path(__file__).resolve().parent
REPOSITORY = HERE.parent


def metadata():
    """名乗り（起動情報④と同じ形）。--metadata はこれを出すだけ、--write-launch-info はこれを書くだけ。
    見せ方と操作（icon・color・kinds・actions）は任意。"""
    return {"app": APP.id, "name": APP.name, "command": cli.launch_command(REPOSITORY), "embed": cli.EMBED,
            "icon": package.icon_record(REPOSITORY, "S"), "color": "teal",  # <リポジトリ>/kobito/icon.svg
            "kinds": [{"kind": "メモ", "dates": "record"}],
            "actions": [{"id": "new", "label": "新しいメモ", "url": "kobito://sample/new", "role": "new"}]}


def start_server(options):
    settings = paths.Settings(paths.app_directory(APP.directory))
    base_path = options.dataset or settings.get("currentDataset")
    # … 基準パスを開き（dataset.read / create）、DatasetLock を取り、history.record(…) を呼ぶ …
    server = PageServer(APP, HERE / "web", router=MyRouter(), parent_origin=options.parent_origin)
    server.start()
    return server


def open_window(options, rest):
    # rest はアプリ独自の引数と kobito:// の URL。
    import webview

    server = start_server(options)
    webview.create_window(APP.name, server.session_url("/index.html"))
    webview.start()


def run_embedded(options, rest):
    # ウインドウを開かず、画面の URL を workspace に知らせる。workspace が終わったら自分も終わる。
    server = start_server(options)
    embed.announce_ready(server.session_url("/index.html"))
    stop = threading.Event()
    embed.exit_when_parent_closes(stop.set)
    stop.wait()


def serve_dev(options, rest):
    # 開発用（launch.py --dev）。options は cli.DevOptions（dataset・port）。ウインドウを開かずにサーバーを動かして返す。
    # cli.run() が URL を出し、Ctrl-C で止める。片付けが要るときは (サーバー, 片付ける関数) を返す。起動情報は書かない。
    server = start_server(embed.EmbedOptions(dataset=options.dataset))
    return server


def main(argv):
    # 画面を開く・埋め込む前に、cli.run() が起動情報④を書き直す（起動のたびに）。
    return cli.run(argv, metadata=metadata, window=open_window, embedded=run_embedded, dev=serve_dev)
```

| `cli.run()` に渡すもの | 呼ばれるとき |
|---|---|
| `metadata()` | `--metadata`（出すだけ）、`--write-launch-info`（書くだけ）、画面を開く・埋め込む前（書き直す）。形が④と合わなければ、`--metadata` と `--write-launch-info` は終了コード 1 |
| `window(options, rest)` | 引数なし、またはアプリ独自の引数・URL だけのとき |
| `embedded(options, rest)` | `--embedded --dataset … --parent-origin …`。渡さなければ、埋め込めないアプリとして `--embedded` を断る（終了コード 2） |
| `dev(options, rest)` | `--dev [--dataset …] [--port …]`。開発中にブラウザで画面を確かめる。渡さなければ `--dev` を断る（終了コード 2）。アプリごとの `scripts/dev_server.py` の代わり |

目印 `kobito-app.json` の `app`・`name` と、`metadata()` の `app`・`name` はそろえます。テストで `manifest.read(<リポジトリ>)` と `metadata()` を比べておくと、ずれに気づけます。

画面の HTML では、次のように読み込みます。

```html
<script src="/kobito/kobito-bridge.js"></script>
```

```js
await kobito.ready;
const [folder] = await kobito.pick("folder");
window.addEventListener("kobito:dropped", (event) => console.log(event.detail.paths));
kobito.listen("changed", (payload) => reload(payload));
```

## 見せ方と操作を名乗る

`metadata()` が返す名乗り（または `launch.write()` の引数）に `name_en`・`icon`・`color`・`kinds`・`actions` を入れると、workspace とランチャーに自然に並びます（形は [CONTRACTS.md ④「見せ方と操作」](CONTRACTS.md#見せ方と操作)、考え方は [APP_INTERFACE.md](APP_INTERFACE.md)）。

| 決まり | 内容 |
|---|---|
| 形が違えば書かない | `write()`・`write_record()` は、約束と合わない項目があれば `ValueError` を出し、ファイルを書きません。どの項目かはメッセージに出ます |
| アイコン | 画像はリポジトリの `kobito/icon.svg`（256 KB まで）に置き、`package.icon_record(<リポジトリ>, <1文字>)` を渡します。起動のたびに書き直すので、フォルダを移しても追いつきます |
| 操作の URL | 自分のアプリID宛てだけ。置き換えは `{today}` だけ。アプリがすでに受け付けている URL を書きます |
| ユーティリティ | 常駐・ユーティリティのアプリは `embed` を渡しません。workspace では起動ボタンだけになり、操作は `command` に URL を足して起動する形で開きます |
| 読む側 | `launch.actions(record)` は `{today}` を置き換えた操作の一覧、`find_action(record, id)` は覚えた `id` から操作を探します。`dates_of(record, kind)` は日付の扱い（無ければ `"event"`） |

書いたあとは `uv run scripts/check_contracts.py --apps` で確かめられます（アイコンの画像が見つかるかも調べます）。

## 単体起動のときにアプリが渡すもの

| `PageServer` の引数 | 用途 |
|---|---|
| `dialogs` | `pick(kind, directory) -> [パス]`。pywebview の `create_file_dialog` を呼ぶ。画面の `kobito.pick()` が使う |
| `notifier` | `notify(title, body)`。OS の通知を出す |
| `controller` | `control(コマンド, 引数) -> bool`。2回目の起動からの受け渡し（`/control/…`） |

単体起動でファイルがドロップされたときは、pywebview のドロップのイベントで実パスを受け取り、`server.publish("kobito:dropped", {"paths": […], "x": …, "y": …})` を呼びます。画面には、埋め込み中と同じ `kobito:dropped` のイベントが届きます。

## テスト

共通部品のテストは kobito-workspace で実行します。どのアプリも、リポジトリの直下で同じ1行で全部のテストを動かします（[APP_PACKAGE.md §10](APP_PACKAGE.md)）。

```bash
uv run python -m unittest discover -s tests -t tests
```

テストは `tests/test_*.py` に置き、`kit.testing.IsolatedTestCase` を土台にします。PC 固有領域・受け渡しフォルダ・`HOME` を一時フォルダに向けるので、実際の設定に触れません。

アプリが書き出したカードと起動情報が約束どおりかは、アプリを動かしたあとに確かめます。リポジトリの形を守っているかは `check_package.py` で確かめます。

```bash
uv run scripts/check_contracts.py --base <基準パス> --apps
uv run scripts/check_package.py <リポジトリ>
```
