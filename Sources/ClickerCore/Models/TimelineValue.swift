import Foundation

enum TimelineValue {
    static let maximum = Double(Int64.max) / 1_000_000_000 - 1

    static func time(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite, value > 0 else { return 0 }
        return min(value, maximum)
    }

    static func ordinal(_ value: Int) -> Int {
        max(0, value)
    }

    static func nextOrdinal(after value: Int) -> Int {
        let current = ordinal(value)
        return current == Int.max ? Int.max : current + 1
    }

    static func adding(_ lhs: TimeInterval, _ rhs: TimeInterval) -> TimeInterval {
        let left = time(lhs)
        let right = time(rhs)
        guard left < maximum,
              right < maximum,
              left <= maximum - right else {
            return maximum
        }
        return left + right
    }
}
