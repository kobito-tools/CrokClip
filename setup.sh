#!/bin/zsh
# InGoodPaste! を、この Mac で使える状態にする（kobito シリーズの初期設定。決まりは kobito-workspace の docs/SETUP.md）。
# 何度動かしても安全。履歴・設定には触れず、書くのは起動情報だけ。sudo は使わない。
set -euo pipefail
cd "${0:A:h}"

APP_NAME="InGoodPaste!"
EXEC_NAME="InGoodPaste"
# 試すときは別のフォルダを指せる（実際のアプリケーションフォルダに触れないため）。
APPLICATIONS_DIR="${KOBITO_APPLICATIONS_DIR:-/Applications}"

usage() {
  cat <<'EOF'
使い方: ./setup.sh [--yes] [--dry-run] [--help]

InGoodPaste! をソースからビルドして、この Mac で使える状態にします。

  （なし）    尋ねる場面では、その都度尋ねます
  --yes       尋ねる場面では、すべて既定の答えを選びます（アプリケーションフォルダへは移しません）
  --dry-run   何をするかを表示するだけで、何も変えません
  --help      この使い方を表示します

Xcode Command Line Tools が必要です。無いときは入れ方を表示して止まります。
EOF
}

yes=false
dry_run=false
for arg in "$@"; do
  case "$arg" in
    --yes) yes=true ;;
    --dry-run) dry_run=true ;;
    --help|-h) usage; exit 0 ;;
    *) echo "知らない引数です: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

say() { print -r -- "$*"; }
step() { print -r -- ""; print -r -- "▶ $*"; }

# はい・いいえを尋ねる。--yes や、答えを読めないときは既定の答え（$2: y か n）にする。
ask() {
  local question="$1" default="$2" hint reply
  [[ "$default" == y ]] && hint="[Y/n]" || hint="[y/N]"
  if $yes; then
    say "$question $hint → 既定の答え（$([[ "$default" == y ]] && echo はい || echo いいえ)）を選びます"
    [[ "$default" == y ]]; return
  fi
  print -n -r -- "$question $hint "
  if ! read -r reply; then reply=""; fi
  [[ -t 0 ]] || print -r -- "$reply"
  [[ -z "$reply" ]] && reply="$default"
  [[ "$reply" == [yY]* ]]
}

$dry_run && say "（--dry-run：何をするかを表示するだけで、何も変えません）"

# 1. 必要な道具
step "1. 必要な道具を確かめます"
if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swiftc >/dev/null 2>&1; then
  say "Xcode Command Line Tools（swiftc）が見つかりません。"
  say "次のコマンドで入れてから、もう一度 ./setup.sh を動かしてください（入れるには管理者のパスワードが要ります）。"
  say ""
  say "  xcode-select --install"
  exit 1
fi
say "Xcode Command Line Tools があります（$(xcrun --find swiftc)）。"

# 2. 自動で入れる道具は無い（Xcode Command Line Tools は入れ方を表示するだけ）。

# 3. ビルド（ソースが新しくなっていることがあるので、毎回作り直す）
step "3. $APP_NAME.app をビルドします"
built="$PWD/$APP_NAME.app"
if $dry_run; then
  say "（--dry-run）./build.sh で $built を作ります"
else
  ./build.sh
  say "ビルドしました: $built"
  say "作り直したので、前に許可していた「アクセシビリティ」「入力監視」は、もう一度許可が要ることがあります。"
fi

# 5. 任意の設定：アプリケーションフォルダへ移す（既定は移さない）
# 起動情報は .app の場所を含むので、移すかどうかを決めてから書き出す（手順4はこのあと）。
step "5. $APP_NAME.app をアプリケーションフォルダへ移すかを決めます"
target="$APPLICATIONS_DIR/$APP_NAME.app"
placed="$built"
if $dry_run; then
  say "（--dry-run）$APPLICATIONS_DIR へ移すかを尋ねます（既定：移さない）"
  if [[ -e "$target" ]]; then
    say "（--dry-run）$target がすでにあるので、置き換えてよいかも尋ねます（--yes では置き換えません）"
  fi
elif ask "$APP_NAME.app を $APPLICATIONS_DIR へ移しますか？" n; then
  move=true
  if [[ -e "$target" ]]; then
    say "$target がすでにあります。"
    if $yes; then
      say "--yes では置き換えません。今あるものはそのままにします。"
      move=false
    elif ! ask "置き換えますか？（今あるものは消えます。履歴と設定は消えません）" n; then
      say "置き換えません。今あるものはそのままにします。"
      move=false
    elif pgrep -x "$EXEC_NAME" >/dev/null 2>&1; then
      say "$APP_NAME が動いているので、置き換えません。終了してから、もう一度 ./setup.sh を動かしてください。"
      move=false
    fi
  fi
  if $move; then
    if { [[ ! -e "$target" ]] || rm -rf "$target"; } && mv "$built" "$target"; then
      placed="$target"
      say "移しました: $placed"
    else
      say "移せませんでした。$built はこのフォルダに残しています。"
    fi
  fi
else
  say "移しません。$built を使います。"
fi

# 4. 起動情報（約束④）を、置いた場所の .app で書き出す
step "4. 起動情報を書き出します"
if $dry_run; then
  say "（--dry-run）$placed/Contents/MacOS/$EXEC_NAME --write-launch-info で書き出します"
else
  "$placed/Contents/MacOS/$EXEC_NAME" --write-launch-info
  say "書き出しました（${KOBITO_CONFIG_DIR:-$HOME/Library/Application Support/kobito-tools}/apps/ingoodpaste.json）。"
fi

# 6. 起動のしかた
step "6. 起動のしかた"
say "  open \"$placed\""
say "起動するとメニューバーに常駐します。⌥⌘V で履歴を開けます。"
say ""
say "貼り付けには「アクセシビリティ」の許可が要ります。初めて貼るときに案内が出るので、"
say "「システム設定」→「プライバシーとセキュリティ」→「アクセシビリティ」で $APP_NAME をオンにしてください。"
say "ペーストスタックを使うときは、同じ場所の「入力監視」もオンにします。"
say ""
say "初期設定が終わりました。"
