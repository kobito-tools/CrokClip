#!/bin/zsh
# 取得・保存・書き戻し・整理・改行の処理を、本物の NSPasteboard（名前付き）と一時フォルダで確かめる。
# 実際のクリップボードと履歴（~/Library/Application Support/CorkClip）には触れない。
set -euo pipefail
cd "${0:A:h}/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# CorkClipApp.swift（@main）以外をハーネスと一緒にコンパイルする。
sources=(Sources/**/*.swift)
sources=(${sources:#Sources/CorkClipApp.swift})
if ! xcrun swiftc -o "$work/harness" $sources tests/harness/main.swift \
  -framework Cocoa -framework SwiftUI -framework Carbon -framework WebKit -framework PDFKit -framework Vision -framework Quartz -framework ServiceManagement -lsqlite3 > "$work/build.log" 2>&1; then
  cat "$work/build.log"; exit 1
fi
# kobito シリーズの PC 固有領域も一時フォルダにする（実際の設定に触れない）。
export KOBITO_CONFIG_DIR="$work/kobito-tools"
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

# カードに残したクリップのDBと、カード（約束③）の形
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
    assert card["v"] == 1 and card["app"] == "corkclip" and card["kind"] and card["title"], card
    assert card["url"].startswith("kobito://corkclip/day/") and datetime.match(card["updated"]), card
    assert re.match(r"^\d{4}-\d{2}-\d{2}$", card["date"]) and len(card.get("text", "")) <= 2000, card
    assert card["id"] not in ids
    ids.add(card["id"])
print(f"ok - カードに残す：DBの更新・移し替えの記録・カード {len(ids)}枚が約束③の形")
PY

# 目印（kobito-app.json。kobito シリーズの決まり：docs/kobito-spec/APP_PACKAGE.md）の形
python3 - kobito-app.json <<'PY'
import json, os, re, sys
path = sys.argv[1]
assert os.path.getsize(path) <= 64 * 1024
marker = json.load(open(path, encoding="utf-8"))
assert marker["format"] == "kobito-app" and marker["v"] == 1 and marker["contracts"] == 1, marker
assert marker["app"] == "corkclip" and re.match(r"^[a-z][a-z0-9-]{0,39}$", marker["app"]) and marker["name"] == "CorkClip", marker
assert marker["kind"] == "native" and "entry" not in marker, marker  # .app で配るので launch.py を持たない
assert marker.get("setup", "setup.sh") == "setup.sh" and os.path.isfile(marker.get("setup", "setup.sh")), marker
assert re.match(r"^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$", marker["repository"]), marker
assert marker["platforms"] == ["macos"] and marker["package"] == 1, marker
for key in ("name_en", "tagline", "tagline_en", "description", "description_en", "bundle_id"):
    assert isinstance(marker[key], str) and marker[key].strip(), key
assert all(len(marker[key]) <= 80 and "\n" not in marker[key] for key in ("tagline", "tagline_en")), marker
build = open("build.sh", encoding="utf-8").read()
assert f"<key>CFBundleIdentifier</key><string>{marker['bundle_id']}</string>" in build, "bundle_id が build.sh と違う"
assert f'VERSION="{marker["version"]}"' in build, "version が build.sh の VERSION と違う"
assert all(os.path.isfile(name) for name in ("kobito/icon.svg", "kobito/icon-1024.png")), "kobito/ のアイコンが無い"
assert not os.path.exists("Setup.command"), "やめた入口 Setup.command が残っている"
print("ok - 目印（kobito-app.json）の形が決まりどおり（native・launch.py なし・バンドルIDと版が build.sh と同じ）")
PY
