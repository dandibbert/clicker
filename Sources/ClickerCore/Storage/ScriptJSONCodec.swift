import Foundation

public enum ScriptTransferError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case invalidDocument(String)
    case encodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "不支持脚本格式版本 \(version)，当前支持版本 1–\(Script.currentSchemaVersion)。"
        case .invalidDocument(let detail):
            "无法读取脚本 JSON：\(detail)"
        case .encodingFailed(let detail):
            "无法导出脚本 JSON：\(detail)"
        }
    }
}

/// The same single-script JSON representation used by ScriptStore, including
/// milliseconds-since-1970 dates and Script's existing v1-v4 migration path.
public enum ScriptJSONCodec {
    public static func encode(_ script: Script) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        do {
            return try encoder.encode(script)
        } catch {
            throw ScriptTransferError.encodingFailed(String(describing: error))
        }
    }

    /// Decoding is read-only: preserve identity and settings for an import
    /// preview, then call importScript or ScriptReuse.duplicate before saving.
    public static func decode(_ data: Data) throws -> Script {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            let header = try decoder.decode(Header.self, from: data)
            let version = header.schemaVersion ?? 1
            guard (1...Script.currentSchemaVersion).contains(version) else {
                throw ScriptTransferError.unsupportedSchemaVersion(version)
            }
            return try decoder.decode(Script.self, from: data)
        } catch let error as ScriptTransferError {
            throw error
        } catch {
            throw ScriptTransferError.invalidDocument(String(describing: error))
        }
    }

    public static func decode(data: Data) throws -> Script {
        try decode(data)
    }

    public static func importScript(from data: Data, now: Date = Date()) throws -> Script {
        ScriptReuse.duplicate(try decode(data), now: now)
    }

    private struct Header: Decodable {
        var schemaVersion: Int?
    }
}

public typealias ScriptTransfer = ScriptJSONCodec
