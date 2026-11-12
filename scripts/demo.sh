#!/bin/zsh
# README のデモ（scripts/demo/demo.html の絵）を、英語版 docs/images/demo.gif と日本語版 docs/images/demo.ja.gif に書き出す。
# Google Chrome、Node.js 22 以降、ffmpeg が必要。
# 使い方: scripts/demo.sh [コマ/秒（既定 15）] [en|ja（省略すると両方）]
set -euo pipefail
cd "${0:A:h}/.."
fps="${1:-15}"
if [[ $# -ge 2 ]]; then langs=("$2"); else langs=(en ja); fi
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p docs/images
for lang in $langs; do
  case "$lang" in
    en) out=docs/images/demo.gif ;;
    ja) out=docs/images/demo.ja.gif ;;
    *) echo "言語は en か ja: $lang" >&2; exit 1 ;;
  esac
  rm -rf "$work/$lang"; mkdir -p "$work/$lang"
  DEMO_LANG="$lang" node scripts/demo/capture.mjs "$work/$lang" "$fps"
  ffmpeg -v error -y -framerate "$fps" -i "$work/$lang/frame%04d.png" \
    -vf "scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    "$out"
  ls -lh "$out"
done
