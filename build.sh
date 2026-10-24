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

rm -rf "$BUILD_DIR"
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
(( $(stat -f %z kobito/icon.svg) <= 262144 )) || { echo "kobito/icon.svg が 256 KB を超えています" >&2; exit 1; }

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

# Apple Silicon・Intelの両方で動くユニバーサルバイナリにする。
for arch in arm64 x86_64; do
  xcrun swiftc -sdk "$SDK" -target "$arch-apple-macosx13.0" -parse-as-library -O \
    Sources/**/*.swift -framework Cocoa -framework SwiftUI -framework Carbon -framework ServiceManagement -framework WebKit -framework PDFKit -framework Vision -lsqlite3 \
    -o "$BUILD_DIR/$EXEC_NAME-$arch"
done
lipo -create "$BUILD_DIR/$EXEC_NAME-arm64" "$BUILD_DIR/$EXEC_NAME-x86_64" -output "$CONTENTS/MacOS/$EXEC_NAME"
# Hardened Runtime を付ける（ほかのプログラムが DYLD_INSERT_LIBRARIES などで CorkClip にコードを読み込ませ、
# CorkClip に与えたアクセシビリティ・入力監視の許可を使うのを防ぐ）。アドホック署名でも付けられる。
codesign --force --sign - --options runtime --timestamp=none "$STAGE"

rm -rf "$APP_NAME.app"
mv "$STAGE" "$APP_NAME.app"
rm -rf "$BUILD_DIR"

# corkclip:// をすぐ使えるように Launch Services へ登録する。
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$PWD/$APP_NAME.app"
echo "$PWD/$APP_NAME.app"
