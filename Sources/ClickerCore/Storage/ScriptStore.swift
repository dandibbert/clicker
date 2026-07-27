import Foundation

public struct ScriptStoreIssue: Error, Equatable, Sendable, Identifiable {
    public enum Operation: String, Equatable, Sendable {
        case list
        case read
        case decode
        case encode
        case createDirectory
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
    private let fileSystem: ScriptStoreFileSystem

    /// 默认目录：~/Library/Application Support/Clicker/scripts/
    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clicker/scripts", isDirectory: true)
    }

    public init(directory: URL) {
        self.directory = directory
        fileSystem = SystemScriptStoreFileSystem()
    }

    init(directory: URL, fileSystem: ScriptStoreFileSystem) {
        self.directory = directory
        self.fileSystem = fileSystem
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    public func save(_ script: Script) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let destination = fileURL(for: script.id)
        let data: Data
        do {
            data = try encoder.encode(script)
        } catch {
            throw ScriptStoreIssue(
                operation: .encode,
                fileName: destination.lastPathComponent,
                message: String(describing: error)
            )
        }
        do {
            try fileSystem.createDirectory(at: directory)
        } catch {
            throw ScriptStoreIssue(
                operation: .createDirectory,
                fileName: destination.lastPathComponent,
                message: String(describing: error)
            )
        }

        let temporary = directory.appendingPathComponent(
            ".\(script.id.uuidString).\(UUID().uuidString).tmp"
        )
        do {
            try fileSystem.write(data, to: temporary)
        } catch {
            try? fileSystem.removeItem(at: temporary)
            throw ScriptStoreIssue(
                operation: .temporaryWrite,
                fileName: destination.lastPathComponent,
                message: String(describing: error)
            )
        }
        defer { try? fileSystem.removeItem(at: temporary) }

        do {
            if fileSystem.fileExists(at: destination) {
                try fileSystem.replaceItem(at: destination, with: temporary)
            } else {
                try fileSystem.moveItem(at: temporary, to: destination)
            }
        } catch {
            throw ScriptStoreIssue(
                operation: .replace,
                fileName: destination.lastPathComponent,
                message: String(describing: error)
            )
        }
    }

    public func delete(id: UUID) throws {
        let url = fileURL(for: id)
        do {
            try fileSystem.removeItem(at: url)
        } catch {
            throw ScriptStoreIssue(
                operation: .delete,
                fileName: url.lastPathComponent,
                message: String(describing: error)
            )
        }
    }

    /// 加载全部脚本，按创建时间升序，并保留每个失败的结构化信息。
    public func loadAll() -> ScriptStoreLoadResult {
        guard fileSystem.fileExists(at: directory) else {
            return ScriptStoreLoadResult(scripts: [], issues: [])
        }
        let files: [URL]
        do {
            files = try fileSystem.contentsOfDirectory(at: directory)
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
                let data = try fileSystem.read(at: url)
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
