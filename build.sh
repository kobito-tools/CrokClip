#!/bin/zsh
# CorkClip.appをこのフォルダ直下に作る。Xcode Command Line Tools（swiftc）が必要。
set -euo pipefail
cd "${0:A:h}"

APP_NAME="CorkClip"
# 実行ファイルの名前。
EXEC_NAME="CorkClip"
VERSION="0.2.0"
BUILD_DIR=".build"
STAGE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$STAGE/Contents"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
STAGES=6
zmodload zsh/datetime

# ---- 進み具合の表示 ----
# setup.sh の見出しの下に並ぶよう、2 文字下げて出す。ターミナルに出す文言は英語。
stage() { print -r -- "  [$1/$STAGES] $2" }

# 経過を出す行。ターミナルなら、終わるまで同じ行で経過秒数を書き換える（Finder から開いた Setup.command も同じ）。
ticker_pid=""
stop_ticker() {
  [[ -n $ticker_pid ]] || return 0
  kill "$ticker_pid" 2>/dev/null || true
  wait "$ticker_pid" 2>/dev/null || true
  ticker_pid=""
  print -n -- $'\r\e[K'
}
# 途中で止めたときも、経過の行と一時ファイルを片付ける。
build_log=""
cleanup() { stop_ticker; [[ -z $build_log ]] || rm -f "$build_log" }
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

# run_long <番号> <見出し> <コマンド…>：時間のかかるコマンドを動かし、終わったら所要秒数を出す。
# コマンドは前で動かし（Ctrl-C がそのまま届く）、経過の表示だけを裏で回す。
# コマンドの出力（警告など）は経過の行を崩さないよう一時ファイルに受け、終わってから出す。
run_long() {
  local number=$1 label=$2 started=$EPOCHSECONDS rc=0
  shift 2
  build_log=$(mktemp "${TMPDIR:-/tmp}/corkclip-build.XXXXXX")
  local log=$build_log
  if [[ -t 1 ]]; then
    (
      local frames='|/-\' i=0
      while true; do
        print -rn -- $'\r'"  [$number/$STAGES] $label ${frames[i % 4 + 1]} $(( EPOCHSECONDS - started ))s "
        i=$(( i + 1 ))
        sleep 0.25
      done
    ) &
    ticker_pid=$!
  else
    stage "$number" "$label ..."
  fi
  "$@" >"$log" 2>&1 || rc=$?
  stop_ticker
  if (( rc )); then
    print -ru2 -- "  [$number/$STAGES] $label: failed (exit code $rc)"
    cat "$log" >&2
    # set -e で止まるときは EXIT の trap が動かないので、ここで消す。
    rm -f "$log"
    build_log=""
    return $rc
  fi
  stage "$number" "$label: done in $(( EPOCHSECONDS - started ))s"
  [[ -s $log ]] && sed 's/^/      /' "$log"
  rm -f "$log"
  build_log=""
  return 0
}

rm -rf "$BUILD_DIR"
stage 1 "Copying the resources and making the icon"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
# 履歴のDBの作成と更新に使う。
cp -R schema "$CONTENTS/Resources/schema"
# 数式画像を描く KaTeX（MIT）と、その描画ページ。
cp -R Resources/. "$CONTENTS/Resources/"
# .app のアイコン（AppIcon.icns）を、シリーズの決まった場所のアイコン（kobito/icon-1024.png）から作る。
mkdir "$BUILD_DIR/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z $size $size kobito/icon-1024.png --out "$BUILD_DIR/AppIcon.iconset/icon_${size}x${size}.png" > /dev/null
  sips -z $((size * 2)) $((size * 2)) kobito/icon-1024.png --out "$BUILD_DIR/AppIcon.iconset/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$CONTENTS/Resources/AppIcon.icns"
# 起動情報（④）の icon.file が指すアイコンの元。リポジトリと同じ kobito/icon.svg の形で入れる（約束で 256 KB まで）。
mkdir -p "$CONTENTS/Resources/kobito"
cp kobito/icon.svg "$CONTENTS/Resources/kobito/icon.svg"
(( $(stat -f %z kobito/icon.svg) <= 262144 )) || { echo "kobito/icon.svg is larger than 256 KB" >&2; exit 1; }

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>ja</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleExecutable</key><string>$EXEC_NAME</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>io.github.kobito-tools.corkclip</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleURLTypes</key><array><dict>
  <key>CFBundleURLName</key><string>io.github.kobito-tools.corkclip</string>
  <key>CFBundleURLSchemes</key><array><string>corkclip</string></array>
</dict></array>
</dict></plist>
PLIST

# Apple Silicon・Intelの両方で動くユニバーサルバイナリにする。ここがビルドの時間のほとんど（1 回あたり数十秒）。
number=2
for arch in arm64 x86_64; do
  [[ $arch == arm64 ]] && label="Compiling for Apple silicon (arm64)" || label="Compiling for Intel (x86_64)"
  run_long $number "$label" xcrun swiftc -sdk "$SDK" -target "$arch-apple-macosx13.0" -parse-as-library -O \
    Sources/**/*.swift -framework Cocoa -framework SwiftUI -framework Carbon -framework ServiceManagement -framework WebKit -framework PDFKit -framework Vision -lsqlite3 \
    -o "$BUILD_DIR/$EXEC_NAME-$arch"
  number=$(( number + 1 ))
done
stage 4 "Combining both into a universal binary"
lipo -create "$BUILD_DIR/$EXEC_NAME-arm64" "$BUILD_DIR/$EXEC_NAME-x86_64" -output "$CONTENTS/MacOS/$EXEC_NAME"
# Hardened Runtime を付ける（ほかのプログラムが DYLD_INSERT_LIBRARIES などで CorkClip にコードを読み込ませ、
# CorkClip に与えたアクセシビリティ・入力監視の許可を使うのを防ぐ）。アドホック署名でも付けられる。
stage 5 "Signing the app (on this Mac only)"
# 「replacing existing signature」（リンカーが付けた仮の署名を置き換える）は毎回出るので、失敗したときだけ出力を見せる。
sign_log=$(codesign --force --sign - --options runtime --timestamp=none "$STAGE" 2>&1) || { print -ru2 -- "$sign_log"; exit 1; }

rm -rf "$APP_NAME.app"
mv "$STAGE" "$APP_NAME.app"
rm -rf "$BUILD_DIR"

# corkclip:// をすぐ使えるように Launch Services へ登録する。
stage 6 "Registering corkclip:// links with macOS"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$PWD/$APP_NAME.app"
print -r -- "  Built: $PWD/$APP_NAME.app"
