import ClickerCore

enum ScriptPlaybackEligibility {
    static func isPlayable(_ script: Script) -> Bool {
        let plan = BlockExpander.plan(for: script)
        return !plan.steps.isEmpty || plan.duration > 0
    }
}
