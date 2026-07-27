import Foundation

protocol ScriptStoreFileSystem: AnyObject {
    func createDirectory(at url: URL) throws
    func fileExists(at url: URL) -> Bool
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func read(at url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
    func replaceItem(at destination: URL, with temporary: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
}

final class SystemScriptStoreFileSystem: ScriptStoreFileSystem {
    private let fileManager = FileManager.default

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    func read(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }

    func replaceItem(at destination: URL, with temporary: URL) throws {
        _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try fileManager.moveItem(at: source, to: destination)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }
}
