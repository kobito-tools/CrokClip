# kobito シリーズの setup.sh が読み込む、共通の部品（zsh）。決まりは docs/SETUP.md。
# 画面に出す文言は英語にする（コメントは日本語のまま）。
#
# 各アプリの setup.sh は、これを読み込んで、自分だけの手順を足すだけにする。
#
#   #!/bin/zsh
#   source "${0:A:h}/sample_app/kobito_kit/setup.zsh" || exit 1
#   kobito_steps+=("Ask whether to start at login (--yes does not register it)")   # 使い方に出す、このアプリだけの手順
#   kobito_setup "Sample" "$@"      # 引数（--yes・--dry-run・--help）を読み、macOS かを確かめ、リポジトリの直下に移る
#   kobito_python_app               # uv を確かめる（無ければ入れるかを尋ねる）・uv sync・launch.py --write-launch-info・repos/ へのリンク
#   kobito_step "Start at login"
#   if kobito_ask "Start Sample when you log in?" n; then
#     kobito_run launchctl …
#   fi
#   kobito_finish                   # 起動のしかたを表示して、終了コード 0 で終わる
#
# ほかのアプリを名指ししない。利用者のデータ（基準パス・設定）には触れない。sudo を使わない。

setopt pipe_fail

# 使い方に出す手順（このあとに、アプリが kobito_steps+=(…) で足す）。
typeset -ga kobito_steps
kobito_steps=(
  "Check that uv is installed (if not, ask whether to install it)"
  "Prepare Python and the dependencies with uv sync"
  "Write the launch info (no window opens)"
  "Record this repository's location in repos/ in the per-Mac folder (a symbolic link)"
)
typeset -g kobito_app_name="" kobito_here="" KOBITO_UV="" kobito_applications="" kobito_app_id=""
# この部品のある場所。部品が使う画像（assets/）は、写した先でもこの隣にある。
typeset -g kobito_kit_here=${${(%):-%x}:A:h}
typeset -gi kobito_yes=0 kobito_dry_run=0

# ---- 表示 ----

kobito_step() { print -r -- "▶ $*" }
kobito_info() { print -r -- "  $*" }
kobito_fail() { print -ru2 -- "✖ $*"; exit 1 }

kobito_usage() {
  local index=1 line
  print -r -- "Usage: ./setup.sh [--yes] [--dry-run] [--help]"
  print
  print -r -- "Sets up $kobito_app_name for use on this Mac."
  for line in $kobito_steps; do
    print -r -- "  $index. $line"
    (( index++ ))
  done
  print -r -- "  $index. Show how to start it"
  print
  print -r -- "  --yes      Choose the default answer for every question"
  print -r -- "  --dry-run  Only show what would be done; change nothing"
  print -r -- "  --help     Show this help"
  print
  print -r -- "Exit codes: 0 success, 1 failure, 2 invalid arguments"
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
      *) print -ru2 -- "Unknown argument: $argument"; kobito_usage >&2; exit 2 ;;
    esac
  done
  kobito_here=${ZSH_ARGZERO:A:h}
  cd "$kobito_here" || kobito_fail "Cannot enter the folder: $kobito_here"
  (( kobito_dry_run )) && print -r -- "(--dry-run: only showing what would be done; nothing will change)"
  print -r -- "Setting up $kobito_app_name."
  [[ $(uname -s) == Darwin ]] || kobito_fail "This setup supports macOS only."
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
    [[ $default == y ]] && kobito_info "$question → yes (--yes)" || kobito_info "$question → no (--yes)"
    [[ $default == y ]]
    return
  fi
  print -n -- "  $question $hint "
  if ! read -r answer && [[ -z $answer ]]; then
    print -r -- "→ no (cannot read an answer)"
    return 1
  fi
  [[ -t 0 ]] || print -r -- "$answer"
  [[ -z $answer ]] && answer=$default
  # 前の版で受け付けていた「はい」も、はいとして扱う。
  [[ $answer == [Yy]* || $answer == はい ]]
}

# kobito_run <コマンド> [引数…]：何を動かすかを表示して動かす。--dry-run なら表示するだけ。
kobito_run() {
  kobito_info "\$ ${(j: :)${(q-)@}}"
  if (( kobito_dry_run )); then
    kobito_info "(skipped: --dry-run)"
    return 0
  fi
  "$@"
}

# kobito_need <コマンド> <入れ方>：無ければ入れ方を表示して止まる（管理者の権限が要るものは、ここで案内だけする）。
kobito_need() {
  if (( $+commands[$1] )); then
    kobito_info "$1: found ($commands[$1])"
  else
    kobito_fail "$1 was not found. $2"
  fi
}

# ---- Python のアプリ ----

# uv を確かめ、無ければ公式の手順で入れるかを尋ねる。見つかった uv は $KOBITO_UV。
kobito_ensure_uv() {
  kobito_step "Checking the required tools"
  if (( $+commands[uv] )); then
    KOBITO_UV=$commands[uv]
    kobito_info "uv: found ($KOBITO_UV)"
    return 0
  fi
  kobito_info "uv: not found"
  kobito_step "Installing uv (official method: curl -LsSf https://astral.sh/uv/install.sh | sh)"
  if (( kobito_dry_run )); then
    kobito_info "(not installed: --dry-run)"
    KOBITO_UV=uv
    return 0
  fi
  if ! kobito_ask "Install uv?" y; then
    kobito_info "Stopping without installing uv. How to install it: https://docs.astral.sh/uv/getting-started/installation/"
    kobito_info "  For example: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
  fi
  (( $+commands[curl] )) || kobito_fail "curl was not found."
  curl -LsSf https://astral.sh/uv/install.sh | sh || kobito_fail "Could not install uv."
  rehash
  (( $+commands[uv] )) || kobito_fail "uv was installed but cannot be found. Open a new terminal window and run this again."
  KOBITO_UV=$commands[uv]
  kobito_info "Installed uv ($KOBITO_UV)"
}

kobito_uv_sync() {
  kobito_step "Preparing Python and the dependencies (uv sync)"
  kobito_run "$KOBITO_UV" sync || kobito_fail "uv sync failed. Check that you are connected to the internet."
}

kobito_write_launch_info() {
  kobito_step "Writing the launch info (uv run launch.py --write-launch-info)"
  kobito_run "$KOBITO_UV" run launch.py --write-launch-info || kobito_fail "Could not write the launch info."
}

# Python のアプリの決まった手順（docs/SETUP.md の 1〜5）をまとめて行う。
kobito_python_app() {
  kobito_check_repository
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

# kobito_check_repository：repos/<アプリID> を調べ、同じ ID を名乗る別の場所のリポジトリがすでに記されていれば、
# 何も書かずに終了コード 1 で止まる（CONTRACTS.md「ID がかぶったとき」：どちらかを勝手に選ばず、知らせて止める）。
# 起動情報の書き出しより前に呼ぶ（かぶったまま書くと、起動情報だけがこのリポジトリに変わって食い違う）。読むだけなので --dry-run でも調べる。
# アプリIDは $kobito_app_id に入れる（読めなければ空）。結果は覚えず、呼ぶたびに調べ直す（途中で別のクローンが記されることもある）。
kobito_check_repository() {
  kobito_app_id=$(plutil -extract app raw -o - "$kobito_here/kobito-app.json" 2>/dev/null)
  [[ $kobito_app_id =~ '^[a-z][a-z0-9-]{0,39}$' ]] || { kobito_app_id=""; return 0 }
  local link="$(kobito_series_directory)/repos/$kobito_app_id" other
  [[ -L $link && -e $link && ${link:A} != ${kobito_here:A} ]] || return 0
  other=$(plutil -extract app raw -o - "$link/kobito-app.json" 2>/dev/null)
  [[ $other == $kobito_app_id ]] || return 0
  kobito_step "A repository with the same app ID exists in another location"
  kobito_info "App ID: $kobito_app_id"
  kobito_info "Recorded repository: ${link:A}"
  kobito_info "This repository: $kobito_here"
  kobito_info "Stopping without changing anything, rather than picking one. To fix it, do one of the following:"
  kobito_info "  - Keep using the recorded one: stop using this repository and remove it"
  kobito_info "  - Switch to this repository: remove the recorded one or the link, then run this again"
  kobito_info "    rm \"$link\""
  kobito_fail "App ID \"$kobito_app_id\" is already used by a repository in another location."
}

# kobito_link_repository：PC 固有領域の repos/<アプリID> に、このリポジトリへのシンボリックリンクを作る。
# 探す側は、どこにクローンしたアプリでも repos/ から見つけられる。アプリIDは kobito-app.json の app。
# 同じ先なら何もしない。先が消えたリンク・同じ ID を名乗らないフォルダへのリンクは張り替える。リンクでない物には触らない。
# 別の場所の、同じ ID を名乗るリポジトリを指していれば止まる（張る直前にも kobito_check_repository で調べ直す）。
kobito_link_repository() {
  kobito_check_repository
  kobito_step "Recording this repository's location (a link in repos/)"
  if [[ -z $kobito_app_id ]]; then
    kobito_info "Cannot read the app ID from kobito-app.json, so no link is made."
    return 0
  fi
  local repos="$(kobito_series_directory)/repos"
  local link="$repos/$kobito_app_id"
  if [[ -L $link ]]; then
    if [[ -e $link && ${link:A} == ${kobito_here:A} ]]; then
      kobito_info "$link: already done"
      return 0
    fi
    if [[ -e $link ]]; then
      kobito_info "$link points to a folder that is not $kobito_app_id (${link:A}), so it will be replaced."
    else
      kobito_info "The target of $link no longer exists, so it will be replaced."
    fi
  elif [[ -e $link ]]; then
    kobito_info "$link is not a symbolic link, so it is left alone. Check what it is, remove it, then run this again."
    return 0
  fi
  kobito_run mkdir -p "$repos" || kobito_fail "Cannot create the folder: $repos"
  kobito_run ln -sfn "$kobito_here" "$link" || kobito_fail "Cannot create the link: $link"
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
  kobito_step "Preparing the kobito-tools folder in the Applications folder"
  if [[ -e $folder || -L $folder ]]; then
    [[ -d $folder ]] || kobito_fail "$folder is not a folder. Another app seems to have put it there. Check what it is, rename or remove it, then run this again."
    kobito_has_custom_icon "$folder" || kobito_fail "$folder seems to have been made by another app (it does not have the kobito series icon). Check what it is, rename or remove it, then run this again."
    kobito_info "$folder: found"
    return 0
  fi
  [[ -f $icon ]] || kobito_fail "The folder icon image was not found: $icon"
  [[ -d $parent ]] || kobito_fail "The Applications folder was not found: $parent"
  [[ -w $parent ]] || kobito_fail "Cannot write to $parent (administrator rights are needed). This setup does not use sudo. Run this again as a user who can write to $parent."
  kobito_run mkdir "$folder" || kobito_fail "Cannot create the folder: $folder"
  # Xcode が無くても動くよう、macOS に入っている osascript（JavaScript）から NSWorkspace でアイコンを付ける。
  kobito_info "\$ osascript -l JavaScript … (set $icon as the icon of $folder)"
  if (( kobito_dry_run )); then
    kobito_info "(skipped: --dry-run)"
    return 0
  fi
  if ! osascript -l JavaScript -e '
ObjC.import("AppKit");
function run(argv) {
  var image = $.NSImage.alloc.initWithContentsOfFile(argv[0]);
  if (image.isNil()) throw new Error("Cannot read the image: " + argv[0]);
  if (!$.NSWorkspace.sharedWorkspace.setIconForFileOptions(image, argv[1], 0)) throw new Error("Cannot set the icon: " + argv[1]);
}' "$icon" "$folder" >/dev/null || ! kobito_has_custom_icon "$folder"; then
    # アイコンの無いフォルダを残すと、次から「別のアプリが作った」とみなしてしまうので、空のうちに消す。
    rm -f -- "$folder/"$'Icon\r'
    rmdir "$folder" 2>/dev/null
    kobito_fail "Could not set the icon of $folder."
  fi
  kobito_info "Created $folder and set its icon."
}

# ---- おわり ----

# kobito_finish [起動のしかたの行…]：起動のしかたを表示して、終了コード 0 で終わる。
# 行を渡さなければ、Python のアプリの起動のしかた（uv run launch.py）を出す。
kobito_finish() {
  kobito_step "All set. To start it, run:"
  local line
  if (( $# )); then
    for line in "$@"; do kobito_info "$line"; done
  else
    kobito_info "cd \"$kobito_here\""
    kobito_info "uv run launch.py"
  fi
  exit 0
}
