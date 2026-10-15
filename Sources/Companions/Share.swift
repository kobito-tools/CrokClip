import Foundation

/// ⑦ 受け渡し（送る。F-16）。選んだクリップの中身を、ほかのアプリの受け渡しの口（④ の receive）へ渡す。
/// 送り先の一覧は、このMacの起動情報から実行時に作る（ほかのアプリの名前は持たない）。
///
/// 送り方：OS の一時フォルダの kobito-share/（権限 700）に <UUID>.json（権限 600）を書き、
/// 口の url の {file} をそのパス（URL エンコード）に置き換えて、送り先の起動情報の command で開く。
/// 受け取った側が読み終えたら消す。24時間より古いものは、送るときに消す。
enum Share {
    /// 送り先1つ（アプリの受け渡しの口）。
    struct Target: Equatable {
        let app: String
        let appName: String
        let command: [String]
        let receive: Series.Receive

        /// 最後に使った送り先として覚えておく名前。
        var key: String { "\(app)/\(receive.id)" }
        /// 送り先の一覧に出す名前（「アプリ名：口の名前」）。
        var title: String { "\(appName)：\(receive.label)" }
    }

    struct Image: Equatable {
        let name: String
        let mimeType: String
        let data: Data
    }

    struct File: Equatable {
        let path: String
        let name: String
    }

    /// 送る中身。
    struct Payload: Equatable {
        var text = ""
        var images: [Image] = []
        var files: [File] = []

        /// 中身の種類（口の accepts と比べる）。
        var kinds: Set<String> {
            var kinds: Set<String> = []
            if !text.isEmpty { kinds.insert("text") }
            if !images.isEmpty { kinds.insert("image") }
            if !files.isEmpty { kinds.insert("file") }
            return kinds
        }

        /// 口が受け取れる種類だけを残す。
        func limited(to accepts: Set<String>) -> Payload {
            Payload(text: accepts.contains("text") ? text : "", images: accepts.contains("image") ? images : [], files: accepts.contains("file") ? files : [])
        }
    }

    static let maxAge: TimeInterval = 24 * 60 * 60

    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["KOBITO_SHARE_DIR"], !override.isEmpty { return URL(fileURLWithPath: override, isDirectory: true) }
        return FileManager.default.temporaryDirectory.appendingPathComponent("kobito-share", isDirectory: true)
    }

    // MARK: - 送り先

    /// 中身の種類のどれかを受け取れる口を、アプリ名・口の名前の順に並べる。自分の口は含めない。
    static func targets(for kinds: Set<String>, launchInfos: [Series.LaunchInfo] = Series.launchInfos()) -> [Target] {
        launchInfos.filter { $0.app != Series.appID }.flatMap { info in
            info.receive.filter { !$0.accepts.isDisjoint(with: kinds) }.map { Target(app: info.app, appName: info.name, command: info.command, receive: $0) }
        }
        .sorted { ($0.appName, $0.receive.label) < ($1.appName, $1.receive.label) }
    }

    // MARK: - 受け渡しファイル

    static func json(_ payload: Payload, now: Date = Date()) throws -> Data {
        var object: [String: Any] = ["kobito": 1, "type": "share", "from": Series.appID, "created": Series.timestamp(now)]
        if !payload.text.isEmpty { object["text"] = payload.text }
        if !payload.images.isEmpty { object["images"] = payload.images.map { ["name": $0.name, "mimeType": $0.mimeType, "base64": $0.data.base64EncodedString()] } }
        if !payload.files.isEmpty { object["files"] = payload.files.map { ["path": $0.path, "name": $0.name] } }
        return try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }

    /// 受け渡しファイルを書き、そのパスを返す。
    static func write(_ payload: Payload, now: Date = Date()) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        cleanup(now: now)
        let file = directory.appendingPathComponent("\(UUID().uuidString.lowercased()).json")
        guard manager.createFile(atPath: file.path, contents: try json(payload, now: now), attributes: [.posixPermissions: 0o600]) else {
            throw StoreError(status: 500, message: "受け渡しファイルを書けません（\(directory.path)）。")
        }
        return file
    }

    /// 24時間より古い受け渡しファイルを消す。
    static func cleanup(now: Date = Date()) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.pathExtension == "json" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
            if now.timeIntervalSince(modified) > maxAge { try? FileManager.default.removeItem(at: file) }
        }
    }

    /// 口の url の {file} を、受け渡しファイルのパス（英数字と -._~ 以外をエンコード）に置き換える。
    static func url(for receive: Series.Receive, file: URL) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return receive.url.replacingOccurrences(of: "{file}", with: file.path.addingPercentEncoding(withAllowedCharacters: allowed) ?? file.path)
    }

    /// 送る。受け渡しファイルを書き、送り先の起動コマンドの最後に URL を足して起動する（シェルを通さない）。
    /// 起動できなければ、書いたファイルを消してエラーにする。
    static func send(_ payload: Payload, to target: Target, launch: ([String]) throws -> Void = run) throws {
        let file = try write(payload.limited(to: target.receive.accepts))
        do { try launch(target.command + [url(for: target.receive, file: file)]) }
        catch { try? FileManager.default.removeItem(at: file); throw error }
    }

    /// コマンドを起動する（終わるのは待たない）。先頭が絶対パスでなければ PATH から探す。
    static func run(_ command: [String]) throws {
        let process = Process()
        if command[0].hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: command[0])
            process.arguments = Array(command.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = command
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
