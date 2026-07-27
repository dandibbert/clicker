import Foundation

public struct ScriptStoreIssue: Error, Equatable, Sendable, Identifiable {
    public enum Operation: String, Equatable, Sendable {
        case list
        case read
        case decode
        case encode
        case temporaryWrite
        case replace
        case delete
    }

    public var operation: Operation
    public var fileName: String?
    public var message: String

    public var id: String {
        "\(operation.rawValue):\(fileName ?? ""):\(message)"
    }

    public init(operation: Operation, fileName: String? = nil, message: String) {
        self.operation = operation
        self.fileName = fileName
        self.message = message
    }
}

public struct ScriptStoreLoadResult: Equatable, Sendable {
    public var scripts: [Script]
    public var issues: [ScriptStoreIssue]

    public init(scripts: [Script], issues: [ScriptStoreIssue]) {
        self.scripts = scripts
        self.issues = issues
    }
}

/// 脚本库：每脚本一个 JSON 文件，文件名 = "\(id).json"。
public final class ScriptStore {
    public let directory: URL

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

    /// 加载全部脚本，按创建时间升序，并保留每个失败的结构化信息。
    public func loadAll() -> ScriptStoreLoadResult {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return ScriptStoreLoadResult(scripts: [], issues: [])
        }
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        } catch {
            return ScriptStoreLoadResult(
                scripts: [],
                issues: [ScriptStoreIssue(operation: .list, message: String(describing: error))]
            )
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var scripts: [Script] = []
        var issues: [ScriptStoreIssue] = []
        for url in files where url.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: url)
                do {
                    scripts.append(try decoder.decode(Script.self, from: data))
                } catch {
                    issues.append(ScriptStoreIssue(
                        operation: .decode,
                        fileName: url.lastPathComponent,
                        message: String(describing: error)
                    ))
                }
            } catch {
                issues.append(ScriptStoreIssue(
                    operation: .read,
                    fileName: url.lastPathComponent,
                    message: String(describing: error)
                ))
            }
        }
        return ScriptStoreLoadResult(
            scripts: scripts.sorted { $0.createdAt < $1.createdAt },
            issues: issues
        )
    }
}
