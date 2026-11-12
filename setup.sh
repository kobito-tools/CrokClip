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
  "Check that no repository with the same app ID is recorded in another location (if one is, stop without changing anything)"
  "Check that the Xcode Command Line Tools are installed (if not, show how to install them and stop)"
  "Build $APP_NAME.app (takes a minute or two)"
  "Ask whether to move it to the kobito-tools folder in the Applications folder (--yes does not move it)"
  "Write the launch info using the .app where it was placed"
  "Record this repository's location in repos/ in the per-Mac folder (a symbolic link)"
  "Show how to grant the Accessibility and Input Monitoring permissions"
)
kobito_setup "$APP_NAME" "$@"
# 同じアプリIDのリポジトリが別の場所に記されていれば、ビルドや起動情報の書き出しより前に、何も変えずに止まる。
kobito_check_repository

kobito_step "Checking the required tools"
if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swiftc >/dev/null 2>&1; then
  kobito_fail "Xcode Command Line Tools (swiftc) not found. Run xcode-select --install in Terminal to install them (an administrator password is required), then run this again."
fi
kobito_info "Xcode Command Line Tools: found"

# ソースが新しくなっていることがあるので、毎回作り直す。
# 時間のかかるコンパイル（2 回、それぞれ数十秒）は、build.sh が段階ごとの行と経過秒数を出す。
kobito_step "Building $APP_NAME.app (takes a minute or two)"
built="$kobito_here/$APP_NAME.app"
kobito_run zsh ./build.sh || kobito_fail "Could not build the app. Check the output above."

# 起動情報は .app の場所を含むので、移すかどうかを決めてから書き出す。
# 置き先は直下ではなく kobito-tools フォルダの下（docs/kobito-spec/SETUP.md §1）。
kobito_step "Deciding whether to move $APP_NAME.app to the Applications folder"
placed="$built"
if kobito_ask "Move $APP_NAME.app to the kobito-tools folder in the Applications folder?" n; then
  kobito_applications_folder
  target="$kobito_applications/$APP_NAME.app"
  move=1
  if [[ -e $target ]]; then
    kobito_info "$target already exists."
    if ! kobito_ask "Replace it? (The existing app is removed. Your history and settings are kept.)" n; then
      kobito_info "Not replacing it. The existing app is left as it is."
      move=0
    elif pgrep -x "$EXEC_NAME" >/dev/null 2>&1; then
      kobito_info "$APP_NAME is running, so it was not replaced. Quit it, then run ./setup.sh again."
      move=0
    fi
  fi
  if (( move )); then
    if { [[ ! -e $target ]] || kobito_run rm -rf "$target"; } && kobito_run mv "$built" "$target"; then
      placed="$target"
      (( kobito_dry_run )) || kobito_info "Moved: $placed"
    else
      kobito_info "Could not move it. $built is left in this folder."
    fi
  fi
else
  kobito_info "Not moving it. Using $built."
fi
# 直下の古い .app は消さない（利用者が片付ける）。
if [[ -e "$APPLICATIONS_DIR/$APP_NAME.app" ]]; then
  kobito_info "An old copy is still at $APPLICATIONS_DIR/$APP_NAME.app. If you no longer use it, quit it and move it to the Trash."
fi

kobito_step "Writing the launch info"
kobito_run "$placed/Contents/MacOS/$EXEC_NAME" --write-launch-info || kobito_fail "Could not write the launch info."

kobito_link_repository

kobito_step "About permissions"
kobito_info "$APP_NAME needs the Accessibility permission to paste (you are asked the first time you paste)."
kobito_info "  1. Open System Settings > Privacy & Security > Accessibility"
kobito_info "  2. Turn on $APP_NAME (if it is not in the list, add it with \"+\")"
kobito_info "  3. To use the paste stack, also turn it on under Input Monitoring in the same place"
kobito_info "Each build changes the signature, so after rebuilding, remove $APP_NAME from these lists with \"-\" and add it again."
[[ $placed == $built ]] && kobito_info "Moving the app to the Applications folder before starting it makes the permissions more likely to stick."

kobito_finish "open \"$placed\"" "Once launched, it stays in the menu bar. Press Option-Command-V to open the history."
