#!/bin/zsh
# パネル・設定の画面・メニューバーのアイコンを、アプリを起動せずに PNG に書き出す（見た目を確かめる用）。
# 使い方: scripts/preview.sh [書き出す先（既定 .build/preview）]
# 見本の履歴は一時フォルダに作り、実際の履歴と設定（~/Library/Application Support/CorkClip）には触れない。
set -euo pipefail
cd "${0:A:h}/.."
out="${${1:-.build/preview}:A}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
sources=(Sources/**/*.swift)
sources=(${sources:#Sources/CorkClipApp.swift})
if ! xcrun swiftc -o "$work/preview" $sources scripts/preview/main.swift \
  -framework Cocoa -framework SwiftUI -framework Carbon -framework WebKit -framework PDFKit -framework Vision -framework Quartz -framework ServiceManagement -lsqlite3 > "$work/build.log" 2>&1; then
  cat "$work/build.log"; exit 1
fi
# 数式を描く KaTeX は、実行ファイルの隣（Bundle.main の resourceURL）から読む。
cp -R Resources/katex "$work/katex"
export KOBITO_CONFIG_DIR="$work/kobito-tools" KOBITO_SHARE_DIR="$work/kobito-share"
"$work/preview" "$work" schema "$out"
