import CryptoKit
import Foundation

/// 共有フォルダ・連携のエラー。
struct StoreError: Error, CustomStringConvertible {
    let status: Int
    let message: String
    var extra: [String: Any] = [:]

    static func badRequest(_ message: String) -> StoreError { StoreError(status: 400, message: message) }
    var description: String { message }
}

/// kobito シリーズ共通の保存フォルダ（約束 ⓪-1。docs/kobito-spec/CONTRACTS.md）で基準パスを扱う。
/// CorkClip の履歴はこのMacの中に置き、基準パスには共有タグと「カードに残す」の分だけを置く。
///
///   <基準パス>/.kobito-tools/
///     dataset.json   format: "kobito-tools-dataset"・ID（シリーズ共通）
///     CorkClip/   lock.json・database/kept.sqlite3・uploads/・cards.jsonl（CorkClip だけが書き込む。KeptCards.swift）
///     Tags/tags.json シリーズで共有するタグ（TagStore.swift）
struct DatasetInfo {
    let basePath: String
    let datasetId: String
    var key: String { Dataset.key(for: basePath) }
}

enum Dataset {
    static let rootName = ".kobito-tools"
    static let directoryName = "CorkClip"
    /// 以前の名前の書き出し先と、そのときの DB の名前。見つけたら ensureDirectories で移す（Pastephant が、いま使われている版）。
    static let renamedDirectories = [(name: "Pastephant", database: "pastephant.sqlite3"), (name: "InGoodPaste", database: "ingoodpaste.sqlite3")]
    static let format = "kobito-tools-dataset"
    static let subdirectories = ["database", "uploads"]

    // MARK: - 場所と識別子

    /// 選んだフォルダをシリーズ共通の規則で絶対パスにする（シンボリックリンクを解決し、.kobito-tools・その中のアプリのフォルダなら基準パスへ読み替える）。
    static func basePath(for url: URL) -> String {
        var resolved = url.standardizedFileURL.path
        if let real = realpath(resolved, nil) { resolved = String(cString: real); free(real) }
        let name = (resolved as NSString).lastPathComponent, parent = (resolved as NSString).deletingLastPathComponent
        if name == rootName { return parent }
        if (parent as NSString).lastPathComponent == rootName { return (parent as NSString).deletingLastPathComponent }
        return resolved
    }

    /// データセットキー（シリーズ共通）。基準パスのSHA-256の先頭16桁。
    static func key(for basePath: String) -> String {
        SHA256.hash(data: Data(basePath.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    static func root(_ basePath: String) -> URL { URL(fileURLWithPath: basePath, isDirectory: true).appendingPathComponent(rootName, isDirectory: true) }

    static func directory(_ basePath: String) -> URL { root(basePath).appendingPathComponent(directoryName, isDirectory: true) }

    static func uploadsDirectory(_ basePath: String) -> URL { directory(basePath).appendingPathComponent("uploads", isDirectory: true) }

    static func tagsFile(_ basePath: String) -> URL { root(basePath).appendingPathComponent("Tags", isDirectory: true).appendingPathComponent("tags.json") }

    /// カードに残したクリップ（KeptCards）。
    static func keptDatabasePath(_ basePath: String) -> String { directory(basePath).appendingPathComponent("database").appendingPathComponent("kept.sqlite3").path }

    /// 以前の書き出し先の DB。初めて kept.sqlite3 を開いたときに中身を移す（KeptCards.importLegacy）。
    static func legacyDatabasePath(_ basePath: String) -> String { directory(basePath).appendingPathComponent("database").appendingPathComponent("corkclip.sqlite3").path }

    private static func datasetFile(_ basePath: String) -> URL { root(basePath).appendingPathComponent("dataset.json") }

    // MARK: - dataset.json

    static func validateId(_ value: String) throws -> String {
        let id = value.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.count <= 60 else { throw StoreError.badRequest("IDは1〜60文字で入力してください。") }
        guard id.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { throw StoreError.badRequest("IDに制御文字は使えません。") }
        return id
    }

    static func read(_ basePath: String) throws -> DatasetInfo? {
        guard let data = try? Data(contentsOf: datasetFile(basePath)) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["format"] as? String == format,
              let id = object["datasetId"] as? String else { throw StoreError(status: 422, message: "保存先のデータ（.kobito-tools/dataset.json）を読み取れません。") }
        return DatasetInfo(basePath: basePath, datasetId: try validateId(id))
    }

    /// .kobito-tools が無ければ一時フォルダで作ってから名前を変えて完成させる（途中で失敗しても中途半端なフォルダを残さない）。
    /// dataset.json の無い .kobito-tools（タグだけがあるなど）なら、dataset.json と CorkClip/ だけを加える。
    static func create(_ basePath: String, datasetId: String) throws -> DatasetInfo {
        let id = try validateId(datasetId)
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: basePath, isDirectory: &isDirectory), isDirectory.boolValue else { throw StoreError.badRequest("保存先はフォルダを指定してください。") }
        guard !manager.fileExists(atPath: datasetFile(basePath).path) else { throw StoreError(status: 409, message: "このフォルダには既に保存先のデータがあります。") }
        let record: [String: Any] = ["format": format, "schemaVersion": 1, "datasetId": id, "createdAt": timestamp(), "revision": 1, "settings": [String: Any](), "legacyRoots": [String: Any]()]
        if manager.fileExists(atPath: root(basePath).path) {
            try ensureDirectories(basePath)
            try writeJSON(record, to: datasetFile(basePath))
            return DatasetInfo(basePath: basePath, datasetId: id)
        }
        let staging = URL(fileURLWithPath: basePath).appendingPathComponent("\(rootName)-creating-\(UUID().uuidString.lowercased())", isDirectory: true)
        do {
            for name in subdirectories { try manager.createDirectory(at: staging.appendingPathComponent(directoryName).appendingPathComponent(name), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
            try writeJSON(record, to: staging.appendingPathComponent("dataset.json"))
            guard !manager.fileExists(atPath: root(basePath).path) else { throw StoreError(status: 409, message: "このフォルダには既に保存先のデータがあります。") }
            try manager.moveItem(at: staging, to: root(basePath))
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
        return DatasetInfo(basePath: basePath, datasetId: id)
    }

    static func ensureDirectories(_ basePath: String) throws {
        try moveRenamedDirectory(basePath)
        for name in subdirectories { try FileManager.default.createDirectory(at: directory(basePath).appendingPathComponent(name), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
    }

    /// 以前の名前（Pastephant・InGoodPaste）で書き出したフォルダとDBを、この名前に移す。
    private static func moveRenamedDirectory(_ basePath: String) throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: directory(basePath).path),
              let renamed = renamedDirectories.first(where: { manager.fileExists(atPath: root(basePath).appendingPathComponent($0.name).path) }) else { return }
        try manager.moveItem(at: root(basePath).appendingPathComponent(renamed.name, isDirectory: true), to: directory(basePath))
        let database = directory(basePath).appendingPathComponent("database", isDirectory: true)
        let legacyDatabase = database.appendingPathComponent(renamed.database)
        if manager.fileExists(atPath: legacyDatabase.path) {
            for suffix in ["", "-journal"] where manager.fileExists(atPath: legacyDatabase.path + suffix) {
                try manager.moveItem(atPath: legacyDatabase.path + suffix, toPath: legacyDatabasePath(basePath) + suffix)
            }
        }
    }

    // MARK: - 共通

    static func timestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func writeJSON(_ value: [String: Any], to url: URL) throws {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        data.append(0x0a)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// 同じ基準パスへ複数のPCの CorkClip が同時に書き出さないための使用中の印（.kobito-tools/CorkClip/lock.json）。
/// 印は CorkClip/ の中に置くので、ほかのアプリの印とは干渉しない。
final class DatasetLock {
    enum State {
        case free
        case mine
        case heldOnThisMac
        case heldElsewhere(hostname: String)
    }

    static let staleInterval: TimeInterval = 120
    static let heartbeatInterval: TimeInterval = 30
    static let hostname: String = {
        var buffer = [CChar](repeating: 0, count: 256)
        return gethostname(&buffer, buffer.count) == 0 ? String(cString: buffer) : ProcessInfo.processInfo.hostName
    }()
    static let machineId: String = {
        if let saved = UserDefaults.standard.string(forKey: "MachineId") { return saved }
        // 以前の名前（Pastephant・InGoodPaste）のときのIDがあれば引き継ぐ。
        if let saved = ["io.github.kobito-tools.pastephant", "io.github.kobito-tools.ingoodpaste"].lazy.compactMap({ UserDefaults(suiteName: $0)?.string(forKey: "MachineId") }).first {
            UserDefaults.standard.set(saved, forKey: "MachineId")
            return saved
        }
        let value = "corkclip-\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(value, forKey: "MachineId")
        return value
    }()

    let basePath: String
    private var startedAt: String?
    private var timer: Timer?
    private var file: URL { Dataset.directory(basePath).appendingPathComponent("lock.json") }

    init(basePath: String) { self.basePath = basePath }

    private func current() -> [String: Any]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func state(now: Date = Date()) -> State {
        guard let lock = current() else { return .free }
        let pid = lock["pid"] as? Int ?? -1, host = lock["hostname"] as? String ?? ""
        if lock["app"] as? String == "corkclip", host == Self.hostname, pid == Int(getpid()) { return .mine }
        let heartbeat = (lock["heartbeatAt"] as? String).flatMap(Dataset.parseTimestamp) ?? .distantPast
        guard now.timeIntervalSince(heartbeat) < Self.staleInterval else { return .free }
        if host == Self.hostname { return pid > 0 && (kill(pid_t(pid), 0) == 0 || errno == EPERM) ? .heldOnThisMac : .free }
        return .heldElsewhere(hostname: host.isEmpty ? "不明なPC" : host)
    }

    var isMine: Bool { if case .mine = state() { return true } else { return false } }

    /// 空いていれば使用中の印を置き、30秒ごとに更新する。印を失ったら（別のPCが期限切れの印を引き継いだなど）更新をやめ、次の保存で取り直す。
    func acquire() throws {
        switch state() {
        case .mine: break
        case .free: try write()
        case .heldOnThisMac: throw StoreError(status: 423, message: "この基準パスはこのMacの別の CorkClip が使用中です。", extra: ["lockHolder": ["hostname": Self.hostname, "samePc": true]])
        case .heldElsewhere(let hostname): throw StoreError(status: 423, message: "この基準パスは「\(hostname)」の CorkClip が使用中です。", extra: ["lockHolder": ["hostname": hostname, "samePc": false]])
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.isMine { try? self.write() } else { self.stop() }
        }
    }

    private func write() throws {
        if startedAt == nil { startedAt = Dataset.timestamp() }
        let lock: [String: Any] = ["app": "corkclip", "machineId": Self.machineId, "hostname": Self.hostname, "pid": Int(getpid()), "startedAt": startedAt!, "heartbeatAt": Dataset.timestamp()]
        try Dataset.writeJSON(lock, to: file)
    }

    private func stop() { timer?.invalidate(); timer = nil; startedAt = nil }

    func release() {
        let owned = isMine
        stop()
        if owned { try? FileManager.default.removeItem(at: file) }
    }
}
