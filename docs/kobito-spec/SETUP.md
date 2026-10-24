# 初期設定（setup.sh）

kobito シリーズの各アプリを、新しい PC で使える状態にするための決まりです。macOS だけに対応します。

| ファイル | 置き場所 | 役割 |
|---|---|---|
| `kobito-app.json` | 各アプリのリポジトリの直下 | 「kobito シリーズのアプリ」と名乗る目印（[APP_PACKAGE.md](APP_PACKAGE.md)） |
| `launch.py` | Python のアプリのリポジトリの直下 | ただ1つの入口。引数の形は全アプリ同じ（[APP_PACKAGE.md](APP_PACKAGE.md)） |
| `setup.sh` | 各アプリのリポジトリの直下 | そのアプリを、この PC で使える状態にする |
| `Setup.command` | 各アプリのリポジトリの直下 | `setup.sh` を Finder からダブルクリックで動かす入口。どのアプリも同じ名前（`<アプリ>-Setup.command` はやめる）。git で実行できる設定（100755） |
| `setup.zsh` | 共通部品の中（Python のアプリは `<パッケージ>/kobito_kit/setup.zsh`、ネイティブのアプリは `docs/kobito-spec/setup.zsh`） | `setup.sh` の共通の手順。`setup.sh` が読み込む（§3） |
| `assets/` | `setup.zsh` と同じ階層 | `setup.zsh` が使う画像（アプリケーションフォルダの `kobito-tools` フォルダのアイコン）。写しにも入る |
| `repos/<アプリID>` | PC 固有領域（`~/Library/Application Support/kobito-tools/repos/`） | `setup.sh` が作る、自分のリポジトリへのシンボリックリンク。workspace はここからもアプリを探す（§1「リポジトリの場所」） |
| `install.sh` | kobito-workspace の直下 | 入れるアプリを対話式に選び、クローンして、各アプリの `setup.sh` を順に動かす（決まりは kobito-workspace の `docs/INSTALL.md`） |

アプリの一覧は、どのファイルにも書きません。`install.sh` は、GitHub の topic `kobito-app` が付いたリポジトリと、その `kobito-app.json` から一覧を作ります（[APP_PACKAGE.md §8](APP_PACKAGE.md)）。各アプリの `setup.sh` は、ほかのアプリを名指ししません（[CONTRACTS.md](CONTRACTS.md) の名指ししない規則）。

1つのアプリだけを設定し直すときは、そのアプリのフォルダで `./setup.sh` を動かすか、`Setup.command` をダブルクリックします。

## 1. setup.sh の決まり

各アプリの `setup.sh` は、次の決まりを守ります。kobito-workspace の `install.sh` と「見つかったアプリ」の登録は、この決まりだけを頼りに呼び出します。

### 呼び出し方

| 引数 | 意味 |
|---|---|
| （なし） | 対話式。入れるかどうかを尋ねる場面では、その都度尋ねる |
| `--yes` | 尋ねる場面では、すべて既定の答え（下の表の「既定」）を選ぶ |
| `--dry-run` | 何をするかを表示するだけで、何も変えない |
| `--help` | 使い方を表示する |

終了コードは、0 が成功、1 が失敗、2 が引数の誤りです。

### する順番

| # | すること | 既定（`--yes`） |
|---|---|---|
| 1 | 必要な道具があるかを確かめる。無ければ入れ方を表示する | — |
| 2 | 足りない道具のうち、公式の手順で入れられるもの（uv・Rust）は、入れるかを尋ねる | 入れる |
| 3 | 動かす準備をする（Python のアプリは `uv sync`、ネイティブのアプリはビルド） | — |
| 4 | 起動情報（約束④）を書き出す。アプリを一度も起動していなくても、workspace に並ぶようにする | — |
| 5 | このリポジトリの場所を、PC 固有領域の `repos/<アプリID>` にシンボリックリンクで記す | — |
| 6 | アプリごとの任意の設定（ログイン時の起動の登録、`.app` をアプリケーションフォルダへ移す、など）を尋ねる | 何もしない |
| 7 | 起動のしかたを表示する | — |

- **何度動かしても安全にする**：2回目以降は、済んでいる手順を飛ばすか、上書きしても困らない形で繰り返します。
- **利用者のデータに触れない**：基準パスの中や、アプリの設定（`settings.json` など）は書き換えません。書くのは起動情報だけです。
- **sudo を使わない**：管理者の権限が要る手順（Xcode Command Line Tools など）は、入れ方を表示するだけにします。
- **表示は日本語**：何をしているかを1行ずつ表示します。

### 起動情報の書き出し

起動情報は、アプリが起動したときにも書かれます。`setup.sh` では、画面を開かずに書き出すため、各アプリに次の引数を用意します。

| アプリの種類 | 書き出し方 |
|---|---|
| Python | `uv run launch.py --write-launch-info`（書き出して、すぐ終わる） |
| ネイティブ（`.app`） | `<アプリ>.app/Contents/MacOS/<実行ファイル> --write-launch-info` |

`.app` の起動情報は、`.app` の場所を含みます。アプリケーションフォルダへ移したあとに、もう一度書き出します。

### リポジトリの場所（`repos/`）

アプリのリポジトリは、どこにクローンしてもかまいません。`setup.sh` は、自分のリポジトリへのシンボリックリンクを PC 固有領域の `repos/<アプリID>` に作ります（アプリIDは `kobito-app.json` の `app`）。workspace は、並びのフォルダに加えて `repos/` も探すので、別の場所にクローンしたアプリにも紹介のカードが付き、「見つかったアプリ」にも出ます（[APP_PACKAGE.md §7](APP_PACKAGE.md)）。

| `repos/<アプリID>` の今の状態 | すること |
|---|---|
| 無い | リンクを作る |
| このリポジトリを指すリンク | 何もしない |
| 先が無いリンク・同じ ID を名乗らないフォルダを指すリンク | このリポジトリへ張り替える |
| 別の場所の、同じ ID を名乗るリポジトリを指すリンク | 張り替えずに知らせる（どちらかを勝手に選ばない。[CONTRACTS.md「ID がかぶったとき」](CONTRACTS.md#id-がかぶったとき)）。`setup.sh` は続ける |
| リンクでない物 | 触らずに知らせる。`setup.sh` は続ける |

### アプリケーションフォルダへ移すとき

`.app` をアプリケーションフォルダへ移すアプリは、`/Applications` の直下ではなく、`/Applications/kobito-tools/` の下に置きます。

| `/Applications/kobito-tools` の今の状態 | すること |
|---|---|
| 無い | フォルダを作り、シリーズのアイコン（`assets/kobito-tools-folder-icon.png`）を付ける |
| あって、アイコンが付いている | そのまま使う |
| あって、アイコンが付いていない・フォルダでない | 別のアプリが作った物とみなし、知らせて止まる（終了コード 1） |

- 移すかどうかを尋ねて「はい」のときだけ用意します（`--yes` の既定は「移さない」）。
- `/Applications` に書き込めないときは、そう知らせて止まります。sudo は使いません。
- `/Applications` の直下に残っている古い `.app` には触りません。
- アイコンは、macOS に入っている `osascript`（JavaScript）から付けます。Xcode は要りません。

workspace の「見つかったアプリ」から登録するときは、workspace がそのアプリのフォルダで `zsh <フォルダ>/setup.sh --yes` を動かします（端末はありません）。尋ねる場面では、既定の答えを選ぶことになります。

## 2. `install.sh` から呼ばれるとき

- `install.sh` は、アプリのフォルダで `zsh ./setup.sh` として呼びます（Google ドライブなどで実行権限が外れていても動くように）。`--yes`・`--dry-run` を付けて呼ぶこともあります。
- `setup.sh` が無い・失敗した（終了コードが 0 でない）アプリは、`install.sh` が飛ばして、最後に一覧で知らせます。
- 新しいアプリを `install.sh` の一覧に出すには、リポジトリに `kobito-app.json` を置き、topic `kobito-app` を付けます（[APP_PACKAGE.md §8・§9](APP_PACKAGE.md)）。`install.sh` は直しません。

## 3. 共通の手順 `setup.zsh`

`--yes`・`--dry-run`・`--help` の読み方、表示、尋ね方、uv を確かめて入れる、`uv sync`、起動情報の書き出しは、どのアプリも同じです。これを共通部品の `setup.zsh` にまとめました。各アプリの `setup.sh` は、これを読み込んで、自分だけの手順を足すだけにします。

### Python のアプリの `setup.sh` の見本

```zsh
#!/bin/zsh
# Sample を、この PC で使える状態にする（macOS だけ）。決まりは sample_app/kobito_kit/docs/SETUP.md。
source "${0:A:h}/sample_app/kobito_kit/setup.zsh" || exit 1
kobito_steps+=("ログインしたときに起動するかを尋ねる（--yes では登録しない）")   # 使い方に出す、このアプリだけの手順
kobito_setup "Sample" "$@"       # 引数を読み、macOS かを確かめ、リポジトリの直下に移る
kobito_python_app                # 1〜5：uv を確かめる（無ければ入れるかを尋ねる）・uv sync・launch.py --write-launch-info・repos/ へのリンク
kobito_step "ログインしたときの起動"
if kobito_ask "ログインしたときに起動しますか？" n; then
  kobito_run launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/com.example.sample.plist"
fi
kobito_finish                    # 起動のしかた（cd … と uv run launch.py）を表示して、終了コード 0 で終わる
```

自分だけの手順が無いアプリは、`kobito_setup`・`kobito_python_app`・`kobito_finish` の3行だけになります（kobito-workspace の `setup.sh` がこの形です）。

### ネイティブのアプリの `setup.sh` の見本

```zsh
#!/bin/zsh
source "${0:A:h}/docs/kobito-spec/setup.zsh" || exit 1
kobito_steps=("Xcode Command Line Tools があるかを確かめる" "Swift でビルドする" "起動情報を書き出す"
              "このリポジトリの場所を PC 固有領域の repos/ に記す（シンボリックリンク）" "アプリケーションフォルダの kobito-tools フォルダへ移すかを尋ねる")
kobito_setup "Sample Native" "$@"
kobito_step "必要な道具を確かめます"
kobito_need xcrun "ターミナルで xcode-select --install を実行して入れてから、もう一度動かしてください。"
kobito_step "ビルドします"
kobito_run ./build.sh || kobito_fail "ビルドできませんでした。"
app="SampleNative.app"
kobito_step "アプリケーションフォルダへ移すか"
if kobito_ask "/Applications/kobito-tools へ移しますか？" n; then
  kobito_applications_folder     # /Applications/kobito-tools を用意する（無ければ作ってアイコンを付ける）。場所は $kobito_applications
  kobito_run rm -rf "$kobito_applications/SampleNative.app"
  kobito_run ditto SampleNative.app "$kobito_applications/SampleNative.app" || kobito_fail "移せませんでした。"
  app="$kobito_applications/SampleNative.app"
fi
kobito_step "起動情報を書き出します"            # .app の場所を含むので、移したあとに書く
kobito_run "$app/Contents/MacOS/SampleNative" --write-launch-info || kobito_fail "起動情報を書き出せませんでした。"
kobito_link_repository           # repos/<アプリID> に、このリポジトリへのリンクを作る
kobito_finish "open \"$app\""
```

`/Applications` の直下に古い `SampleNative.app` が残っていても、`setup.sh` は消しません（利用者が片付けます）。

### 部品の一覧

| 部品 | すること |
|---|---|
| `kobito_steps` | 使い方（`--help`）に出す手順の配列。既定は Python のアプリの手順。`+=` で足すか、`=` で置き換える。最後の「起動のしかたを表示する」は自動で足す |
| `kobito_setup <表示名> "$@"` | 引数を読む（`--help` は使い方を出して 0、知らない引数は 2）。macOS でなければ止まる。`setup.sh` のあるフォルダに移る。`~/.local/bin` を `PATH` に足す |
| `kobito_step`・`kobito_info`・`kobito_fail` | 表示（`▶ 手順`・字下げの説明・`✖` を出して終了コード 1） |
| `kobito_ask <問い> <y か n>` | 尋ねる。`--yes` なら既定の答え。答えを読めない（端末が無い）ときは「いいえ」 |
| `kobito_run <コマンド…>` | 動かすコマンドを表示して動かす。`--dry-run` なら表示するだけ |
| `kobito_need <コマンド> <入れ方>` | 無ければ入れ方を出して止まる（sudo が要る道具の案内に使う） |
| `kobito_ensure_uv`・`kobito_uv_sync`・`kobito_write_launch_info` | uv の確かめ（`$KOBITO_UV`）・`uv sync`・`uv run launch.py --write-launch-info` |
| `kobito_link_repository` | `kobito-app.json` の `app` を読み、PC 固有領域の `repos/<アプリID>` にこのリポジトリへのシンボリックリンクを作る（§1「リポジトリの場所」）。`--dry-run` なら表示するだけ。PC 固有領域は `KOBITO_CONFIG_DIR` で変えられる（テスト用） |
| `kobito_python_app` | 上の4つ（uv の確かめ・`uv sync`・起動情報・`repos/` へのリンク）をまとめて行う |
| `kobito_applications_folder` | アプリケーションフォルダの `kobito-tools` フォルダを用意し、場所を `$kobito_applications` に入れる（§1「アプリケーションフォルダへ移すとき」）。移すと答えたときだけ呼ぶ。アプリケーションフォルダは `KOBITO_APPLICATIONS_DIR`（既定 `/Applications`）で変えられる（テスト用） |
| `kobito_finish [行…]` | 起動のしかたを表示して、終了コード 0 で終わる。行を渡さなければ `uv run launch.py` を出す |
| `$kobito_yes`・`$kobito_dry_run`・`$kobito_here` | 引数の状態と、リポジトリの場所 |
| `$kobito_kit_here` | `setup.zsh` のあるフォルダ（隣に `assets/` がある） |

- `setup.zsh` は写しなので、直接書き換えません。直すときは kobito-workspace の `kobito_workspace/kit/setup.zsh` を直して写し直します。
- `Setup.command` は、どのアプリも同じ中身でかまいません（`cd "${0:A:h}" && zsh ./setup.sh "$@"` のあと、Enter を待って閉じる）。
