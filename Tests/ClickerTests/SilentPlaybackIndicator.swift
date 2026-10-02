@testable import Clicker

@MainActor
final class SilentPlaybackIndicator: PlaybackIndicatorPresenting {
    func show(progress: PlaybackProgress, onStop: @escaping () -> Void) {}
    func update(progress: PlaybackProgress) {}
    func close() {}
}
