#!/bin/zsh
# CorkClip を、この Mac で使える状態にする（macOS だけ）。
# 決まりは docs/kobito-spec/SETUP.md。共通の手順は docs/kobito-spec/setup.zsh にある。
# 何度動かしても安全。履歴・設定には触れず、書くのは起動情報だけ。sudo は使わない。

source "${0:A:h}/docs/kobito-spec/setup.zsh" || exit 1

APP_NAME="CorkClip"
EXEC_NAME="CorkClip"
# 試すときは KOBITO_APPLICATIONS_DIR で別のフォルダを指せる（実際のアプリケーションフォルダに触れないため）。
APPLICATIONS_DIR="${KOBITO_APPLICATIONS_DIR:-/Applications}"

kobito_steps=(
  "Xcode Command Line Tools があるかを確かめる（無ければ入れ方を表示して止まる）"
  "$APP_NAME.app をビルドする"
  "アプリケーションフォルダの kobito-tools フォルダへ移すかを尋ねる（--yes では移さない）"
  "起動情報を、置いた場所の .app で書き出す"
  "このリポジトリの場所を PC 固有領域の repos/ に記す（シンボリックリンク）"
  "許可（アクセシビリティ・入力監視）の案内を表示する"
)
kobito_setup "$APP_NAME" "$@"

kobito_step "必要な道具を確かめます"
if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swiftc >/dev/null 2>&1; then
  kobito_fail "Xcode Command Line Tools（swiftc）が見つかりません。ターミナルで xcode-select --install を実行して入れてから（管理者のパスワードが要ります）、もう一度動かしてください。"
fi
kobito_info "Xcode Command Line Tools: あります（$(xcrun --find swiftc)）"

# ソースが新しくなっていることがあるので、毎回作り直す。
kobito_step "$APP_NAME.app をビルドします"
built="$kobito_here/$APP_NAME.app"
kobito_run zsh ./build.sh || kobito_fail "ビルドできませんでした。"
(( kobito_dry_run )) || kobito_info "作り直したので、前に許可していた「アクセシビリティ」「入力監視」は、もう一度許可が要ることがあります。"

# 起動情報は .app の場所を含むので、移すかどうかを決めてから書き出す。
# 置き先は直下ではなく kobito-tools フォルダの下（docs/kobito-spec/SETUP.md §1）。
kobito_step "$APP_NAME.app をアプリケーションフォルダへ移すかを決めます"
placed="$built"
if kobito_ask "$APP_NAME.app を $APPLICATIONS_DIR/kobito-tools へ移しますか？" n; then
  kobito_applications_folder
  target="$kobito_applications/$APP_NAME.app"
  move=1
  if [[ -e $target ]]; then
    kobito_info "$target がすでにあります。"
    if ! kobito_ask "置き換えますか？（今あるものは消えます。履歴と設定は消えません）" n; then
      kobito_info "置き換えません。今あるものはそのままにします。"
      move=0
    elif pgrep -x "$EXEC_NAME" >/dev/null 2>&1; then
      kobito_info "$APP_NAME が動いているので、置き換えません。終了してから、もう一度 ./setup.sh を動かしてください。"
      move=0
    fi
  fi
  if (( move )); then
    if { [[ ! -e $target ]] || kobito_run rm -rf "$target"; } && kobito_run mv "$built" "$target"; then
      placed="$target"
      (( kobito_dry_run )) || kobito_info "移しました: $placed"
    else
      kobito_info "移せませんでした。$built はこのフォルダに残しています。"
    fi
  fi
else
  kobito_info "移しません。$built を使います。"
fi
# 直下の古い .app は消さない（利用者が片付ける）。
if [[ -e "$APPLICATIONS_DIR/$APP_NAME.app" ]]; then
  kobito_info "前の置き場所の $APPLICATIONS_DIR/$APP_NAME.app が残っています。使わないなら、終了してからゴミ箱へ移してください。"
fi

kobito_step "起動情報を書き出します"
kobito_run "$placed/Contents/MacOS/$EXEC_NAME" --write-launch-info || kobito_fail "起動情報を書き出せませんでした。"

kobito_link_repository

kobito_step "許可について"
kobito_info "貼り付けには「アクセシビリティ」の許可が要ります。初めて貼るときに案内が出るので、"
kobito_info "「システム設定」→「プライバシーとセキュリティ」→「アクセシビリティ」で $APP_NAME をオンにしてください。"
kobito_info "ペーストスタックを使うときは、同じ場所の「入力監視」もオンにします。"

kobito_finish "open \"$placed\"" "起動するとメニューバーに常駐します。⌥⌘V で履歴を開けます。"
