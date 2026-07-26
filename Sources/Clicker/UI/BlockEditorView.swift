import SwiftUI
import ClickerCore

struct BlockEditorView: View {
    let block: ActionBlock
    let onSave: (ActionBlock) -> Void

    var body: some View {
        Text("编辑器施工中")
            .padding(40)
    }
}
