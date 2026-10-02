import CoreGraphics
import ClickerCore

/// Uses Core Graphics display coordinates, matching recorded events. NSScreen's
/// bottom-left origin cannot be compared directly with CGEvent coordinates.
@MainActor
final class PlaybackCoordinateValidator: PlaybackCoordinateValidating {
    typealias DisplayBoundsProvider = @MainActor () -> [CGRect]
    private let displayBounds: DisplayBoundsProvider?

    /// Nil checks finite values without requiring a connected display (test use).
    init(displayBounds: DisplayBoundsProvider? = nil) {
        self.displayBounds = displayBounds
    }

    static func system() -> PlaybackCoordinateValidator {
        PlaybackCoordinateValidator(displayBounds: activeDisplayBounds)
    }

    func failureMessage(for plan: PlaybackPlan) -> String? {
        let bounds = displayBounds?()
        for step in plan.steps {
            guard let point = coordinate(in: step.action) else { continue }
            guard point.x.isFinite, point.y.isFinite else {
                return "脚本包含无效的鼠标坐标，请修改后再回放。"
            }
            if let bounds, !bounds.contains(where: { $0.contains(point) }) {
                return "脚本中的鼠标坐标不在当前显示器内，请检查显示器布局或修改坐标后再回放。"
            }
        }
        return nil
    }

    private func coordinate(in action: StepAction) -> CGPoint? {
        switch action {
        case .mouseMove(let x, let y, _),
             .mouseDown(let x, let y, _, _, _),
             .mouseUp(let x, let y, _, _, _),
             .mouseDrag(let x, let y, _, _),
             .scroll(let x, let y, _, _, _):
            return CGPoint(x: x, y: y)
        case .keyDown, .keyUp:
            return nil
        }
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return displays.prefix(Int(count)).map { CGDisplayBounds($0) }
    }
}
