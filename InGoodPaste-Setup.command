#!/bin/zsh
# setup.sh を Finder からダブルクリックで動かす入口。
cd "${0:A:h}"
./setup.sh "$@"
status=$?
echo ""
read "reply?Enterキーで閉じます..."
exit $status
