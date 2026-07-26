import SwiftUI
import ClickerCore

/// 单个动作块的行内展示：彩色图标 + 标题 + 摘要，类 Shortcuts 风格。
struct BlockRowView: View {
    let block: ActionBlock
    let isActive: Bool  // 回放中高亮

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isActive ? Color.accentColor : .clear, lineWidth: 1.5)
        )
    }

    private var icon: String {
        switch block {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .click: return "cursorarrow.click"
        case .drag: return "hand.draw"
        case .scroll: return "computermouse"
        case .typeText: return "keyboard"
        case .shortcut: return "command"
        case .wait: return "clock"
        }
    }

    private var color: Color {
        switch block {
        case .move: return .blue
        case .click: return .indigo
        case .drag: return .purple
        case .scroll: return .teal
        case .typeText: return .green
        case .shortcut: return .orange
        case .wait: return .gray
        }
    }

    private var title: String {
        switch block {
        case .move: return "移动鼠标"
        case .click(let c):
            let btn = c.button == .right ? "右键" : (c.clickCount >= 2 ? "双击" : "单击")
            return btn
        case .drag: return "拖拽"
        case .scroll: return "滚动"
        case .typeText: return "输入文本"
        case .shortcut(let s): return KeyCodeMap.shortcutDisplay(keyCode: s.keyCode, flags: s.flags)
        case .wait: return "等待"
        }
    }

    private var subtitle: String {
        func fmt(_ v: Double) -> String { String(format: "%.0f", v) }
        func fmtT(_ v: TimeInterval) -> String { String(format: "%.1f 秒", v) }
        switch block {
        case .move(let m):
            guard let a = m.points.first, let b = m.points.last else { return "" }
            return "(\(fmt(a.x)), \(fmt(a.y))) → (\(fmt(b.x)), \(fmt(b.y)))・\(fmtT(m.duration))"
        case .click(let c):
            return "(\(fmt(c.x)), \(fmt(c.y)))"
        case .drag(let d):
            guard let a = d.points.first, let b = d.points.last else { return "" }
            return "(\(fmt(a.x)), \(fmt(a.y))) → (\(fmt(b.x)), \(fmt(b.y)))・\(fmtT(d.duration))"
        case .scroll(let s):
            let total = s.steps.reduce(0.0) { $0 + $1.dy }
            return total <= 0 ? "向下 \(fmt(-total)) px" : "向上 \(fmt(total)) px"
        case .typeText(let t):
            return "\"\(t.text)\""
        case .shortcut:
            return "快捷键"
        case .wait(let w):
            return fmtT(w.duration)
        }
    }
}
