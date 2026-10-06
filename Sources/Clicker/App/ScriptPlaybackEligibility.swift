import ClickerCore

enum ScriptPlaybackEligibility {
    static func isPlayable(_ script: Script) -> Bool {
        if script.playbackDeliveryMode == .background {
            guard let target = script.targetBundleIdentifier, !target.isEmpty else {
                return false
            }
        }

        let plan = BlockExpander.plan(for: script)
        return !plan.steps.isEmpty || plan.duration > 0
    }
}
