# kobito シリーズの setup.sh が読み込む、共通の部品（zsh）。決まりは docs/SETUP.md。
#
# 各アプリの setup.sh は、これを読み込んで、自分だけの手順を足すだけにする。
#
#   #!/bin/zsh
#   source "${0:A:h}/sample_app/kobito_kit/setup.zsh" || exit 1
#   kobito_steps+=("ログインしたときに起動するかを尋ねる（--yes では登録しない）")   # 使い方に出す、このアプリだけの手順
#   kobito_setup "Sample" "$@"      # 引数（--yes・--dry-run・--help）を読み、macOS かを確かめ、リポジトリの直下に移る
#   kobito_python_app               # uv を確かめる（無ければ入れるかを尋ねる）・uv sync・launch.py --write-launch-info・repos/ へのリンク
#   kobito_step "ログインしたときの起動"
#   if kobito_ask "ログインしたときに起動しますか？" n; then
#     kobito_run launchctl …
#   fi
#   kobito_finish                   # 起動のしかたを表示して、終了コード 0 で終わる
#
# ほかのアプリを名指ししない。利用者のデータ（基準パス・設定）には触れない。sudo を使わない。

setopt pipe_fail

# 使い方に出す手順（このあとに、アプリが kobito_steps+=(…) で足す）。
typeset -ga kobito_steps
kobito_steps=(
  "uv があるかを確かめる（無ければ、入れるかを尋ねる）"
  "uv sync で Python と部品を用意する"
  "起動情報を書き出す（画面は開きません）"
  "このリポジトリの場所を PC 固有領域の repos/ に記す（シンボリックリンク）"
)
typeset -g kobito_app_name="" kobito_here="" KOBITO_UV="" kobito_applications=""
# この部品のある場所。部品が使う画像（assets/）は、写した先でもこの隣にある。
typeset -g kobito_kit_here=${${(%):-%x}:A:h}
typeset -gi kobito_yes=0 kobito_dry_run=0

# ---- 表示 ----

kobito_step() { print -r -- "▶ $*" }
kobito_info() { print -r -- "  $*" }
kobito_fail() { print -ru2 -- "✖ $*"; exit 1 }

kobito_usage() {
  local index=1 line
  print -r -- "使い方: ./setup.sh [--yes] [--dry-run] [--help]"
  print
  print -r -- "$kobito_app_name を、この PC で使える状態にします。"
  for line in $kobito_steps; do
    print -r -- "  $index. $line"
    (( index++ ))
  done
  print -r -- "  $index. 起動のしかたを表示する"
  print
  print -r -- "  --yes      尋ねる場面では、すべて既定の答えを選ぶ"
  print -r -- "  --dry-run  何をするかを表示するだけで、何も変えない"
  print -r -- "  --help     この使い方を表示する"
  print
  print -r -- "終了コード: 0 成功・1 失敗・2 引数の誤り"
}

# ---- はじめ ----

# kobito_setup <表示名> "$@"：引数を読み、macOS かを確かめ、setup.sh のあるフォルダ（リポジトリの直下）に移る。
kobito_setup() {
  kobito_app_name=$1
  shift
  local argument
  for argument in "$@"; do
    case $argument in
      --yes) kobito_yes=1 ;;
      --dry-run) kobito_dry_run=1 ;;
      -h|--help) kobito_usage; exit 0 ;;
      *) print -ru2 -- "知らない引数です: $argument"; kobito_usage >&2; exit 2 ;;
    esac
  done
  kobito_here=${ZSH_ARGZERO:A:h}
  cd "$kobito_here" || kobito_fail "フォルダに入れません: $kobito_here"
  (( kobito_dry_run )) && print -r -- "（--dry-run：表示するだけで、何も変えません）"
  print -r -- "$kobito_app_name の初期設定を始めます。"
  [[ $(uname -s) == Darwin ]] || kobito_fail "この初期設定は macOS だけに対応しています。"
  # 公式の手順で入れた uv は ~/.local/bin に入る。PATH にまだ無くても見つけられるようにする。
  path=("$HOME/.local/bin" "$HOME/.cargo/bin" $path)
  return 0
}

# ---- 尋ねる・動かす ----

# kobito_ask <問い> <既定の答え y か n>：はいなら 0。--yes なら尋ねずに既定の答え。
# 答えを読めない（端末が無い・流し込んだ答えが尽きた）ときは「いいえ」にする（勝手に入れない）。
kobito_ask() {
  local question=$1 default=${2:-y} answer hint
  [[ $default == y ]] && hint="[Y/n]" || hint="[y/N]"
  if (( kobito_yes )); then
    [[ $default == y ]] && kobito_info "$question → はい（--yes）" || kobito_info "$question → いいえ（--yes）"
    [[ $default == y ]]
    return
  fi
  print -n -- "  $question $hint "
  if ! read -r answer && [[ -z $answer ]]; then
    print -r -- "→ いいえ（答えを読めません）"
    return 1
  fi
  [[ -t 0 ]] || print -r -- "$answer"
  [[ -z $answer ]] && answer=$default
  [[ $answer == [Yy]* || $answer == はい ]]
}

# kobito_run <コマンド> [引数…]：何を動かすかを表示して動かす。--dry-run なら表示するだけ。
kobito_run() {
  kobito_info "\$ ${(j: :)${(q-)@}}"
  if (( kobito_dry_run )); then
    kobito_info "（--dry-run のため、しません）"
    return 0
  fi
  "$@"
}

# kobito_need <コマンド> <入れ方>：無ければ入れ方を表示して止まる（管理者の権限が要るものは、ここで案内だけする）。
kobito_need() {
  if (( $+commands[$1] )); then
    kobito_info "$1: あります（$commands[$1]）"
  else
    kobito_fail "$1 が見つかりません。$2"
  fi
}

# ---- Python のアプリ ----

# uv を確かめ、無ければ公式の手順で入れるかを尋ねる。見つかった uv は $KOBITO_UV。
kobito_ensure_uv() {
  kobito_step "必要な道具を確かめます"
  if (( $+commands[uv] )); then
    KOBITO_UV=$commands[uv]
    kobito_info "uv: あります（$KOBITO_UV）"
    return 0
  fi
  kobito_info "uv: ありません"
  kobito_step "uv を入れます（公式の手順：curl -LsSf https://astral.sh/uv/install.sh | sh）"
  if (( kobito_dry_run )); then
    kobito_info "（--dry-run のため、入れません）"
    KOBITO_UV=uv
    return 0
  fi
  if ! kobito_ask "uv を入れますか？" y; then
    kobito_info "uv を入れずに終わります。入れ方: https://docs.astral.sh/uv/getting-started/installation/"
    kobito_info "  例: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
  fi
  (( $+commands[curl] )) || kobito_fail "curl が見つかりません。"
  curl -LsSf https://astral.sh/uv/install.sh | sh || kobito_fail "uv を入れられませんでした。"
  rehash
  (( $+commands[uv] )) || kobito_fail "uv を入れましたが、見つかりません。ターミナルを開き直して、もう一度動かしてください。"
  KOBITO_UV=$commands[uv]
  kobito_info "uv を入れました（$KOBITO_UV）"
}

kobito_uv_sync() {
  kobito_step "Python と部品を用意します（uv sync）"
  kobito_run "$KOBITO_UV" sync || kobito_fail "uv sync に失敗しました。インターネットに接続されているかを確かめてください。"
}

kobito_write_launch_info() {
  kobito_step "起動情報を書き出します（uv run launch.py --write-launch-info）"
  kobito_run "$KOBITO_UV" run launch.py --write-launch-info || kobito_fail "起動情報を書き出せませんでした。"
}

# Python のアプリの決まった手順（docs/SETUP.md の 1〜5）をまとめて行う。
kobito_python_app() {
  kobito_ensure_uv
  kobito_uv_sync
  kobito_write_launch_info
  kobito_link_repository
}

# ---- リポジトリの場所（repos/） ----

# PC 固有領域（kobito-tools/）。テストでは KOBITO_CONFIG_DIR で変えられる。
kobito_series_directory() {
  print -r -- "${KOBITO_CONFIG_DIR:-$HOME/Library/Application Support/kobito-tools}"
}

# kobito_link_repository：PC 固有領域の repos/<アプリID> に、このリポジトリへのシンボリックリンクを作る。
# 探す側は、どこにクローンしたアプリでも repos/ から見つけられる。アプリIDは kobito-app.json の app。
# 同じ先なら何もしない。先が消えたリンクは張り替える。別の場所の、同じ ID を名乗るリポジトリを指していれば、
# どちらかを勝手に選ばず、張り替えずに知らせる（CONTRACTS.md「ID がかぶったとき」）。リンクでない物には触らない。
kobito_link_repository() {
  kobito_step "このリポジトリの場所を記します（repos/ へのリンク）"
  local app other
  app=$(plutil -extract app raw -o - "$kobito_here/kobito-app.json" 2>/dev/null)
  if [[ ! $app =~ '^[a-z][a-z0-9-]{0,39}$' ]]; then
    kobito_info "kobito-app.json からアプリIDを読めないので、リンクを作りません。"
    return 0
  fi
  local repos="$(kobito_series_directory)/repos"
  local link="$repos/$app"
  if [[ -L $link ]]; then
    if [[ -e $link && ${link:A} == ${kobito_here:A} ]]; then
      kobito_info "$link: 済んでいます"
      return 0
    fi
    if [[ -e $link ]]; then
      other=$(plutil -extract app raw -o - "$link/kobito-app.json" 2>/dev/null)
      if [[ $other == $app ]]; then
        kobito_info "$link は、同じアプリID（$app）を名乗る別の場所のリポジトリ（${link:A}）を指しています。"
        kobito_info "どちらかを勝手に選ばず、張り替えません。使うほうを決めて、もう片方を片付けるか、リンクを消してから、もう一度動かしてください。"
        return 0
      fi
      kobito_info "$link は、$app を名乗らないフォルダ（${link:A}）を指しているので、張り替えます。"
    else
      kobito_info "$link の先が無くなっているので、張り替えます。"
    fi
  elif [[ -e $link ]]; then
    kobito_info "$link はシンボリックリンクではないので、触りません。中を確かめて、片付けてから、もう一度動かしてください。"
    return 0
  fi
  kobito_run mkdir -p "$repos" || kobito_fail "フォルダを作れません: $repos"
  kobito_run ln -sfn "$kobito_here" "$link" || kobito_fail "リンクを作れません: $link"
}

# ---- アプリケーションフォルダ（.app を移すアプリ） ----

# kobito_has_custom_icon <フォルダ>：Finder のカスタムアイコンが付いているか（Icon\r があり、FinderInfo に印がある）。
kobito_has_custom_icon() {
  [[ -f $1/$'Icon\r' ]] || return 1
  local info
  info=$(xattr -px com.apple.FinderInfo "$1" 2>/dev/null) || return 1
  info=${info//[[:space:]]/}
  # FinderInfo の 9 バイトめ（finderFlags の上位）の 0x04 が kHasCustomIcon（0x0400）。
  [[ ${#info} -ge 18 ]] && (( 0x${info[17,18]} & 0x04 ))
}

# kobito_applications_folder：アプリケーションフォルダの下の kobito-tools フォルダを用意し、その場所を $kobito_applications に入れる。
# 無ければ作って、シリーズのアイコンを付ける。あってアイコンが付いていれば、そのまま使う。
# あるのにアイコンが無い・フォルダでないときは、別のアプリが作ったものとみなして止まる。sudo は使わない。
# 移すかどうかを尋ねて「はい」のときだけ呼び、.app は "$kobito_applications/<アプリ>.app" に置く。
# アプリケーションフォルダの直下に残っている古い .app には触らない。テストでは KOBITO_APPLICATIONS_DIR で場所を変えられる。
kobito_applications_folder() {
  local parent=${KOBITO_APPLICATIONS_DIR:-/Applications}
  local folder="$parent/kobito-tools" icon="$kobito_kit_here/assets/kobito-tools-folder-icon.png"
  kobito_applications=$folder
  kobito_step "アプリケーションフォルダの kobito-tools フォルダを用意します"
  if [[ -e $folder || -L $folder ]]; then
    [[ -d $folder ]] || kobito_fail "$folder はフォルダではありません。別のアプリが置いた物のようです。中を確かめて、名前を変えるか片付けてから、もう一度動かしてください。"
    kobito_has_custom_icon "$folder" || kobito_fail "$folder は、別のアプリが作ったフォルダのようです（kobito シリーズのアイコンが付いていません）。中を確かめて、名前を変えるか片付けてから、もう一度動かしてください。"
    kobito_info "$folder: あります"
    return 0
  fi
  [[ -f $icon ]] || kobito_fail "フォルダのアイコンの画像が見つかりません: $icon"
  [[ -d $parent ]] || kobito_fail "アプリケーションフォルダが見つかりません: $parent"
  [[ -w $parent ]] || kobito_fail "$parent に書き込めません（管理者の権限が要ります）。この初期設定は sudo を使いません。$parent に書き込める利用者で、もう一度動かしてください。"
  kobito_run mkdir "$folder" || kobito_fail "フォルダを作れません: $folder"
  # Xcode が無くても動くよう、macOS に入っている osascript（JavaScript）から NSWorkspace でアイコンを付ける。
  kobito_info "\$ osascript -l JavaScript …（$icon を $folder のアイコンにする）"
  if (( kobito_dry_run )); then
    kobito_info "（--dry-run のため、しません）"
    return 0
  fi
  if ! osascript -l JavaScript -e '
ObjC.import("AppKit");
function run(argv) {
  var image = $.NSImage.alloc.initWithContentsOfFile(argv[0]);
  if (image.isNil()) throw new Error("画像を読めません: " + argv[0]);
  if (!$.NSWorkspace.sharedWorkspace.setIconForFileOptions(image, argv[1], 0)) throw new Error("アイコンを付けられません: " + argv[1]);
}' "$icon" "$folder" >/dev/null || ! kobito_has_custom_icon "$folder"; then
    # アイコンの無いフォルダを残すと、次から「別のアプリが作った」とみなしてしまうので、空のうちに消す。
    rm -f -- "$folder/"$'Icon\r'
    rmdir "$folder" 2>/dev/null
    kobito_fail "$folder にアイコンを付けられませんでした。"
  fi
  kobito_info "$folder を作り、アイコンを付けました。"
}

# ---- おわり ----

# kobito_finish [起動のしかたの行…]：起動のしかたを表示して、終了コード 0 で終わる。
# 行を渡さなければ、Python のアプリの起動のしかた（uv run launch.py）を出す。
kobito_finish() {
  kobito_step "準備ができました。起動するには、次を実行します。"
  local line
  if (( $# )); then
    for line in "$@"; do kobito_info "$line"; done
  else
    kobito_info "cd \"$kobito_here\""
    kobito_info "uv run launch.py"
  fi
  exit 0
}
