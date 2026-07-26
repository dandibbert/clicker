import Foundation

/// 脚本库：每脚本一个 JSON 文件，文件名 = "\(id).json"。
public final class ScriptStore {
    public let directory: URL
    /// 最近一次 loadAll 中无法解析的文件名，供 UI 提示。
    public private(set) var corruptFiles: [String] = []

    /// 默认目录：~/Library/Application Support/Clicker/scripts/
    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clicker/scripts", isDirectory: true)
    }

    public init(directory: URL) {
        self.directory = directory
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    public func save(_ script: Script) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(script)
        try data.write(to: fileURL(for: script.id), options: .atomic)
    }

    public func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: fileURL(for: id))
    }

    /// 加载全部脚本，按创建时间升序。损坏文件跳过并记录到 corruptFiles。
    public func loadAll() -> [Script] {
        corruptFiles = []
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var scripts: [Script] = []
        for url in files where url.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: url)
                scripts.append(try decoder.decode(Script.self, from: data))
            } catch {
                corruptFiles.append(url.lastPathComponent)
            }
        }
        return scripts.sorted { $0.createdAt < $1.createdAt }
    }
}
