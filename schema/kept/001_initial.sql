-- 基準パスの .kobito-tools/InGoodPaste/database/kept.sqlite3。workspace に残したクリップ（F-17）。
-- 同じ基準パスに複数のMacの InGoodPaste! が残すので、このMacの履歴ではなく基準パスに置き、残した時点の中身を写しておく
-- （履歴の項目が期限で消えても、残した物は消えない）。cards.jsonl（約束③）はここから日ごとに作り直す。

CREATE TABLE kept_clips (
  id TEXT PRIMARY KEY,                      -- <マシンID>-<履歴の項目ID>。以前の書き出しから移した物は legacy-<メモID>
  day TEXT NOT NULL,                        -- 残した日（YYYY-MM-DD。残したMacの日付）
  kept_at TEXT NOT NULL,                    -- 残した日時（ISO 8601、時差付き）
  heading TEXT NOT NULL DEFAULT '',         -- 時刻・コピー元・タグの1行
  text TEXT NOT NULL DEFAULT '',            -- 文字（数式の元の式・ファイルのパス・画像の文字を含む）
  tag_ids TEXT NOT NULL DEFAULT '[]',       -- 共有タグ（tags.json）のIDの配列（JSON）
  image TEXT                                -- uploads/ に保存した PNG の名前
) STRICT;
CREATE INDEX kept_clips_day_idx ON kept_clips(day, kept_at);

-- 一度だけ行う処理の記録（以前の書き出し先からの移し替えなど）。
CREATE TABLE kept_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
) STRICT;
