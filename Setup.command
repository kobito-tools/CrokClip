#!/bin/zsh
# Finder からダブルクリックで、CorkClip の初期設定（setup.sh）を動かす入口。
cd "${0:A:h}" || exit 1
zsh ./setup.sh "$@"
result=$?
print
read -rs "?Press Enter to close."
print
exit $result
