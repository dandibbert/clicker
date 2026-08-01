import SwiftUI
import ClickerCore

/// Compatibility wrapper for call sites that still use the legacy row name.
struct BlockRowView: View {
    let block: ActionBlock
    let isActive: Bool

    var body: some View {
        ActionCardView(block: block, isActive: isActive)
    }
}
