#!/bin/zsh
# 取得・保存・書き戻し・整理・改行の処理を、本物の NSPasteboard（名前付き）と一時フォルダで確かめる。
# 実際のクリップボードと履歴（~/Library/Application Support/InGoodPaste）には触れない。
set -euo pipefail
cd "${0:A:h}/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# InGoodPasteApp.swift（@main）以外をハーネスと一緒にコンパイルする。
sources=(Sources/**/*.swift)
sources=(${sources:#Sources/InGoodPasteApp.swift})
if ! xcrun swiftc -o "$work/harness" $sources tests/harness/main.swift \
  -framework Cocoa -framework SwiftUI -framework Carbon -framework WebKit -framework PDFKit -framework Vision -framework Quartz -framework ServiceManagement -lsqlite3 > "$work/build.log" 2>&1; then
  cat "$work/build.log"; exit 1
fi
# kobito シリーズの PC 固有領域と受け渡しのフォルダも一時フォルダにする（実際の設定に触れない）。
export KOBITO_CONFIG_DIR="$work/kobito-tools" KOBITO_SHARE_DIR="$work/kobito-share"
"$work/harness" "$work" schema Resources/katex | tee "$work/harness.log"
grep -q "すべて成功" "$work/harness.log"

# DBの形と整合性
python3 - "$work/store/database/history.sqlite3" <<'PY'
import sqlite3, sys, os
db = sqlite3.connect(sys.argv[1])
applied = [row[0] for row in db.execute("SELECT version FROM schema_migrations ORDER BY version")]
bundled = sorted(name for name in os.listdir("schema") if name.endswith(".sql"))
assert applied == bundled, (applied, bundled)
assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
assert db.execute("PRAGMA journal_mode").fetchone()[0] == "wal"
print(f"ok - DBの更新 {len(applied)}件・整合性OK・WAL")
PY

# workspace に残したクリップのDBと、カード（約束③）の形
python3 - "$work/harness.log" <<'PY'
import json, re, sqlite3, sys, os
values = dict(line.strip().split("=", 1) for line in open(sys.argv[1]) if line.startswith(("KEPT_DB=", "CARDS=")))
db = sqlite3.connect(values["KEPT_DB"])
applied = [row[0] for row in db.execute("SELECT version FROM schema_migrations ORDER BY version")]
bundled = sorted(name for name in os.listdir("schema/kept") if name.endswith(".sql"))
assert applied == bundled, (applied, bundled)
assert db.execute("PRAGMA journal_mode").fetchone()[0] == "delete"
assert db.execute("SELECT count(*) FROM kept_meta WHERE key = 'legacy_imported'").fetchone()[0] == 1
datetime = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})$")
ids = set()
for line in open(values["CARDS"], encoding="utf-8"):
    card = json.loads(line)
    assert card["v"] == 1 and card["app"] == "ingoodpaste" and card["kind"] and card["title"], card
    assert card["url"].startswith("kobito://ingoodpaste/day/") and datetime.match(card["updated"]), card
    assert re.match(r"^\d{4}-\d{2}-\d{2}$", card["date"]) and len(card.get("text", "")) <= 2000, card
    assert card["id"] not in ids
    ids.add(card["id"])
print(f"ok - workspace に残す：DBの更新・移し替えの記録・カード {len(ids)}枚が約束③の形")
PY
