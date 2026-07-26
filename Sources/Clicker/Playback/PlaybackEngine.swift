import Foundation
import AppKit
import ClickerCore

/// 按时间轴投递回放步骤，支持重复与中断。
@MainActor
final class PlaybackEngine {
    private var task: Task<Void, Never>?
    private var escMonitor: Any?

    var isPlaying: Bool { task != nil }

    /// onIteration(第几轮，从 1 计)、onBlock(当前块 ID)、onFinish 均在主线程回调。
    func play(script: Script,
              onIteration: @escaping (Int) -> Void,
              onBlock: @escaping (UUID?) -> Void,
              onFinish: @escaping () -> Void) {
        stop()
        let steps = BlockExpander.expand(script.blocks)
        guard !steps.isEmpty else { onFinish(); return }

        // Esc 紧急停止（全局监听按键；需辅助功能权限，与录制同权限）
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {  // Esc
                Task { @MainActor in
                    guard let self, self.isPlaying else { return }
                    self.stop()
                    onFinish()
                }
            }
        }

        let repeatCount = script.repeatForever ? Int.max : max(1, script.repeatCount)
        let interval = max(0, script.repeatInterval)

        task = Task { [weak self] in
            for iteration in 1...repeatCount {
                if Task.isCancelled { break }
                onIteration(iteration)
                let start = ContinuousClock.now
                var lastBlockID: UUID?
                for step in steps {
                    if Task.isCancelled { break }
                    // 睡到该步骤的绝对时刻，保证整体时间轴不漂移；乱序步骤直接投递
                    let target = start.advanced(by: .seconds(step.t))
                    if target > ContinuousClock.now {
                        try? await Task.sleep(until: target, clock: .continuous)
                    }
                    if Task.isCancelled { break }
                    if step.blockID != lastBlockID {
                        lastBlockID = step.blockID
                        onBlock(step.blockID)
                    }
                    EventPoster.post(step.action)
                }
                if Task.isCancelled { break }
                if iteration < repeatCount && interval > 0 {
                    onBlock(nil)
                    try? await Task.sleep(for: .seconds(interval))
                }
            }
            let wasCancelled = Task.isCancelled
            await MainActor.run { [weak self] in
                self?.cleanUpMonitor()
                self?.task = nil
                if !wasCancelled { onFinish() }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        cleanUpMonitor()
    }

    private func cleanUpMonitor() {
        if let m = escMonitor {
            NSEvent.removeMonitor(m)
            escMonitor = nil
        }
    }
}
