# kobito シリーズの setup.sh が読み込む、共通の部品（zsh）。決まりは docs/SETUP.md。
#
# 各アプリの setup.sh は、これを読み込んで、自分だけの手順を足すだけにする。
#
#   #!/bin/zsh
#   source "${0:A:h}/sample_app/kobito_kit/setup.zsh" || exit 1
#   kobito_steps+=("ログインしたときに起動するかを尋ねる（--yes では登録しない）")   # 使い方に出す、このアプリだけの手順
#   kobito_setup "Sample" "$@"      # 引数（--yes・--dry-run・--help）を読み、macOS かを確かめ、リポジトリの直下に移る
#   kobito_python_app               # uv を確かめる（無ければ入れるかを尋ねる）・uv sync・launch.py --write-launch-info
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
)
typeset -g kobito_app_name="" kobito_here="" KOBITO_UV=""
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

# Python のアプリの決まった手順（docs/SETUP.md の 1〜4）をまとめて行う。
kobito_python_app() {
  kobito_ensure_uv
  kobito_uv_sync
  kobito_write_launch_info
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
