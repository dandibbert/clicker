import Foundation
import ClickerCore

protocol ScriptPersisting: AnyObject {
    func loadAll() -> ScriptStoreLoadResult
    func save(_ script: Script) throws
    func delete(id: UUID) throws
}

extension ScriptStore: ScriptPersisting {}
