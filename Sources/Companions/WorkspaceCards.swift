import Foundation

/// workspace に残す（F-17）。⌘S や「自動で残すタグ」で残したクリップを、基準パスの InGoodPaste! 自身の DB に写し、
/// 日ごとに1枚のカード（約束③）にして <基準パス>/.kobito-tools/InGoodPaste/cards.jsonl に書き出す。
/// workspace はこのカードを HOME・カレンダー・検索に並べ、押すと kobito://ingoodpaste/day/<日付> で InGoodPaste! を開く。
///
///   <基準パス>/.kobito-tools/InGoodPaste/
///     database/kept.sqlite3   残したクリップ（schema/kept/）
///     uploads/<UUID>.png      残した画像（PNG にそろえる。カードには入れない）
///     cards.jsonl             日ごとのカード
///     lock.json               同じ基準パスへ複数のMacが同時に書かないための印（DatasetLock）
enum WorkspaceCards {
    /// 残す1件。
    struct Entry {
        let clipID: Int
        let copiedAt: Date
        let appName: String?
        let tagNames: [String]
        let tagIDs: [String]
        let text: String?
        let latex: String?
        let filePaths: [String]
        let ocrText: String?
        /// PNG にそろえた画像。
        let image: Data?
    }

    static let kind = "クリップ"
    static let maxText = 2000
    static let legacyImportedKey = "legacy_imported"

    static func cardsFile(_ basePath: String) -> URL { Dataset.directory(basePath).appendingPathComponent("cards.jsonl") }

    /// 「10月15日のクリップ」。
    static func title(day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return "\(day)のクリップ" }
        return "\(parts[1])月\(parts[2])日のクリップ"
    }

    static func url(day: String) -> String { "kobito://\(Series.appID)/day/\(day)" }

    // MARK: - 残す

    /// 残して、カードを書き直す。同じ項目をもう一度残したら、中身を新しくする。
    static func keep(_ entries: [Entry], basePath: String, schemaDirectory: URL, now: Date = Date()) throws {
        guard !entries.isEmpty else { return }
        guard try Dataset.read(basePath) != nil else { throw StoreError(status: 409, message: "基準パスに共有フォルダ（.kobito-tools）がありません。") }
        try withDatabase(basePath, schemaDirectory: schemaDirectory) { database in
            let day = Series.day(now), keptAt = Series.timestamp(now)
            var saved: [String] = []
            defer { if !saved.isEmpty { saved.forEach { try? FileManager.default.removeItem(at: Dataset.uploadsDirectory(basePath).appendingPathComponent($0)) } } }
            try database.transaction {
                for entry in entries {
                    var imageName: String?
                    if let image = entry.image {
                        let name = "\(UUID().uuidString.lowercased()).png"
                        guard FileManager.default.createFile(atPath: Dataset.uploadsDirectory(basePath).appendingPathComponent(name).path, contents: image, attributes: [.posixPermissions: 0o600]) else {
                            throw StoreError(status: 500, message: "画像を保存できませんでした。")
                        }
                        saved.append(name)
                        imageName = name
                    }
                    let tags = String(data: try JSONSerialization.data(withJSONObject: entry.tagIDs), encoding: .utf8) ?? "[]"
                    try database.run("INSERT OR REPLACE INTO kept_clips(id, day, kept_at, heading, text, tag_ids, image) VALUES (?, ?, ?, ?, ?, ?, ?)",
                                     "\(DatasetLock.machineId)-\(entry.clipID)", day, keptAt, heading(entry), body(entry), tags, imageName)
                }
            }
            saved.removeAll()
            try writeCards(database, basePath: basePath)
        }
    }

    /// カードを書き直す（以前の書き出し先からの移し替えもここで行う）。起動時と基準パスを変えたときに呼ぶ。
    static func refresh(basePath: String, schemaDirectory: URL) throws {
        guard try Dataset.read(basePath) != nil else { return }
        try withDatabase(basePath, schemaDirectory: schemaDirectory) { try writeCards($0, basePath: basePath) }
    }

    private static func withDatabase(_ basePath: String, schemaDirectory: URL, _ body: (SQLiteDatabase) throws -> Void) throws {
        try Dataset.ensureDirectories(basePath)
        let lock = DatasetLock(basePath: basePath)
        try lock.acquire()
        defer { lock.release() }
        // 雲のドライブに置いても壊れないよう、WAL ではなく DELETE で開く。
        let database = try SQLiteDatabase(path: Dataset.keptDatabasePath(basePath), journal: .delete)
        try database.migrate(schemaDirectory: schemaDirectory)
        try importLegacy(database, basePath: basePath)
        try body(database)
    }

    private static func heading(_ entry: Entry) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return ([formatter.string(from: entry.copiedAt), entry.appName].compactMap { $0 } + (entry.tagNames.isEmpty ? [] : [entry.tagNames.map { "#\($0)" }.joined(separator: " ")])).joined(separator: "・")
    }

    private static func body(_ entry: Entry) -> String {
        var lines: [String] = []
        if let latex = entry.latex { lines.append(latex) }
        else if let text = entry.text, !text.isEmpty { lines.append(text) }
        lines += entry.filePaths
        if let ocr = entry.ocrText, !ocr.isEmpty, entry.text == nil { lines.append(ocr) }
        return lines.joined(separator: "\n")
    }

    // MARK: - カード

    /// 日ごとに1枚のカード。
    static func cards(_ database: SQLiteDatabase) throws -> [[String: Any]] {
        var days: [String: (tags: [String], texts: [String], updated: String, latest: Date)] = [:]
        for row in try database.query("SELECT day, kept_at, text, tag_ids FROM kept_clips ORDER BY day, kept_at, id") {
            guard let day = row["day"] as? String, let keptAt = row["kept_at"] as? String, let keptDate = Dataset.parseTimestamp(keptAt) else { continue }
            var item = days[day] ?? ([], [], keptAt, keptDate)
            let tags = (row["tag_ids"] as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String] } ?? []
            for tag in tags where !item.tags.contains(tag) { item.tags.append(tag) }
            if let text = row["text"] as? String, !text.isEmpty { item.texts.append(text) }
            if keptDate >= item.latest { item.updated = keptAt; item.latest = keptDate }
            days[day] = item
        }
        return days.keys.sorted().map { day in
            let item = days[day]!
            var card: [String: Any] = ["v": 1, "app": Series.appID, "id": "clips-\(day)", "kind": kind, "title": title(day: day),
                                       "date": day, "url": url(day: day), "updated": item.updated]
            if !item.tags.isEmpty { card["tags"] = item.tags }
            let text = item.texts.joined(separator: "\n")
            if !text.isEmpty { card["text"] = String(String.UnicodeScalarView(text.unicodeScalars.prefix(maxText))) }
            return card
        }
    }

    /// 全件を一時ファイルに書いてから置き換える。
    static func writeCards(_ database: SQLiteDatabase, basePath: String) throws {
        var data = Data()
        for card in try cards(database) {
            data.append(try JSONSerialization.data(withJSONObject: card, options: [.sortedKeys, .withoutEscapingSlashes]))
            data.append(0x0a)
        }
        try Series.writeAtomic(data, to: cardsFile(basePath))
    }

    // MARK: - 以前の書き出し先からの移し替え

    /// 以前は、残したクリップを日ごとのメモとして別の形の DB（database/ingoodpaste.sqlite3 の memos 表）に書いていた。
    /// 初めて開いたときに、そのメモを1件ずつ kept_clips に写す（元の DB は消さずに残す）。画像は uploads/ にそのまま残る。
    static func importLegacy(_ database: SQLiteDatabase, basePath: String) throws {
        guard try database.first("SELECT value FROM kept_meta WHERE key = ?", legacyImportedKey) == nil else { return }
        let path = Dataset.legacyDatabasePath(basePath)
        var rows: [(id: String, day: String, keptAt: String, text: String, tags: [String])] = []
        if FileManager.default.fileExists(atPath: path) {
            let legacy = try SQLiteDatabase(path: path, journal: .delete)
            if try legacy.first("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'memos'") != nil {
                let hasTags = try legacy.first("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'memo_tags'") != nil
                for memo in try legacy.query("SELECT id, body_text, created_at, updated_at FROM memos WHERE deleted_at IS NULL ORDER BY created_at") {
                    guard let id = memo["id"] as? String, let created = (memo["created_at"] as? String).flatMap(Dataset.parseTimestamp) else { continue }
                    let updated = (memo["updated_at"] as? String).flatMap(Dataset.parseTimestamp) ?? created
                    let tags = hasTags ? try legacy.query("SELECT tag_id FROM memo_tags WHERE memo_id = ? ORDER BY tag_id", id).compactMap { $0["tag_id"] as? String } : []
                    rows.append((id, Series.day(created), Series.timestamp(updated), memo["body_text"] as? String ?? "", tags))
                }
            }
        }
        try database.transaction {
            for row in rows {
                let tags = String(data: try JSONSerialization.data(withJSONObject: row.tags), encoding: .utf8) ?? "[]"
                try database.run("INSERT OR IGNORE INTO kept_clips(id, day, kept_at, text, tag_ids) VALUES (?, ?, ?, ?, ?)", "legacy-\(row.id)", row.day, row.keptAt, row.text, tags)
            }
            try database.run("INSERT INTO kept_meta(key, value) VALUES (?, ?)", legacyImportedKey, Series.timestamp())
        }
    }
}
