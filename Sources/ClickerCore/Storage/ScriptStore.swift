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

/// Optional capability, so existing application stores and test doubles do not
/// have to implement recovery to satisfy their ordinary persistence contract.
public protocol ScriptRecovering: AnyObject {
    func loadRecentlyDeleted() -> ScriptStoreLoadResult
    func restoreRecentlyDeleted(id: UUID) throws -> Script
}

/// 脚本库：每脚本一个 JSON 文件，文件名 = "\(id).json"。
public final class ScriptStore: ScriptRecovering {
    public let directory: URL
    private let fileSystem: ScriptStoreFileSystem

    /// Kept inside this library, with no automatic purge or permanent deletion.
    public var recentlyDeletedDirectory: URL {
        directory.appendingPathComponent("Recently Deleted", isDirectory: true)
    }

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
        _ = try moveToRecentlyDeleted(id: id)
    }

    @discardableResult
    public func moveToRecentlyDeleted(id: UUID) throws -> URL {
        let url = fileURL(for: id)
        let archived = recentlyDeletedDirectory.appendingPathComponent(url.lastPathComponent)
        do {
            // Never destroy an earlier recoverable copy with the same identity.
            guard !fileSystem.fileExists(at: archived) else {
                throw ScriptStoreIssue(
                    operation: .delete,
                    fileName: url.lastPathComponent,
                    message: "最近删除中已存在同一脚本，请先恢复该副本。"
                )
            }
            try fileSystem.createDirectory(at: recentlyDeletedDirectory)
            try fileSystem.moveItem(at: url, to: archived)
            return archived
        } catch let issue as ScriptStoreIssue {
            throw issue
        } catch {
            throw ScriptStoreIssue(
                operation: .delete,
                fileName: url.lastPathComponent,
                message: String(describing: error)
            )
        }
    }

    public func loadRecentlyDeleted() -> ScriptStoreLoadResult {
        loadAll(in: recentlyDeletedDirectory)
    }

    /// Restores the archived file only if its original identity is not in use.
    /// A failed read, decode or move leaves the recoverable file untouched.
    public func restoreRecentlyDeleted(id: UUID) throws -> Script {
        let archived = recentlyDeletedDirectory.appendingPathComponent("\(id.uuidString).json")
        let destination = fileURL(for: id)
        guard !fileSystem.fileExists(at: destination) else {
            throw ScriptStoreIssue(
                operation: .replace,
                fileName: destination.lastPathComponent,
                message: "脚本库中已有同一脚本，恢复不会覆盖现有副本。"
            )
        }
        let data: Data
        do {
            data = try fileSystem.read(at: archived)
        } catch {
            throw ScriptStoreIssue(operation: .read, fileName: archived.lastPathComponent,
                                   message: String(describing: error))
        }
        let script: Script
        do {
            script = try ScriptJSONCodec.decode(data)
            guard script.id == id else {
                throw ScriptTransferError.invalidDocument("脚本标识与归档文件名不一致。")
            }
        } catch {
            throw ScriptStoreIssue(operation: .decode, fileName: archived.lastPathComponent,
                                   message: String(describing: error))
        }
        do {
            try fileSystem.createDirectory(at: directory)
            try fileSystem.moveItem(at: archived, to: destination)
        } catch {
            throw ScriptStoreIssue(operation: .replace, fileName: destination.lastPathComponent,
                                   message: String(describing: error))
        }
        return script
    }

    /// 加载全部脚本，按创建时间升序，并保留每个失败的结构化信息。
    public func loadAll() -> ScriptStoreLoadResult {
        loadAll(in: directory)
    }

    private func loadAll(in directory: URL) -> ScriptStoreLoadResult {
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
