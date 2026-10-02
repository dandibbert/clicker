import SwiftUI
import AppKit
import ClickerCore
import Darwin

@main
struct ClickerApp: App {
    @NSApplicationDelegateAdaptor(ClickerApplicationDelegate.self) private var appDelegate
    @StateObject private var state: AppState
    private let applicationServices: ApplicationServiceCoordinator?
    private let smokeTest: StartupSmokeTest?

    init() {
        let smoke = StartupSmokeTest(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
        smokeTest = smoke
        smoke?.beginStartupMonitoring()
        let s: AppState
        if let smoke {
            // Never load real scripts or register global input hooks in installer QA.
            s = AppState(store: ScriptStore(directory: smoke.storeDirectory))
            s.hasPermission = false
        } else {
            s = AppState()
        }
        _state = StateObject(wrappedValue: s)
        applicationServices = smoke == nil ? ApplicationServiceCoordinator(state: s) : nil
        if smoke == nil { s.setUp() }
    }

    var body: some Scene {
        Window("Clicker", id: "main") {
            MainView()
                .environmentObject(state)
                .preferredColorScheme(state.appearancePreference.colorScheme)
                .frame(minWidth: 760, minHeight: 480)
                .disabled(smokeTest != nil)
                .onAppear {
                    appDelegate.state = state
                    if let smokeTest {
                        smokeTest.mainViewDidAppear()
                    } else {
                        applicationServices?.start()
                    }
                }
        }

        Settings {
            ClickerSettingsView()
                .environmentObject(state)
                .preferredColorScheme(state.appearancePreference.colorScheme)
        }
    }
}

/// Explicit, inert launch mode used only by the packaged-app CI smoke check.
/// The normal SwiftUI scene still creates its real AppKit window, but no service,
/// shortcut, recording, or playback is started and its controls are disabled.
@MainActor
final class StartupSmokeTest {
    let storeDirectory: URL
    let reportURL: URL?
    private var hasStarted = false
    private var mainViewAppeared = false
    private var didFinishLaunching = false
    private var launchObserver: NSObjectProtocol?

    init?(arguments: [String], environment: [String: String] = [:]) {
        guard environment["CLICKER_SMOKE_TEST"] == "1" || arguments.contains("--smoke-test") else { return nil }
        if let path = environment["CLICKER_SMOKE_REPORT"], path.hasPrefix("/") {
            reportURL = URL(fileURLWithPath: path)
        } else if let index = arguments.firstIndex(of: "--smoke-report"),
           arguments.indices.contains(index + 1),
           arguments[index + 1].hasPrefix("/") {
            reportURL = URL(fileURLWithPath: arguments[index + 1])
        } else {
            reportURL = nil
        }
        storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-Smoke-\(UUID().uuidString)", isDirectory: true)
    }

    func beginStartupMonitoring() {
        guard !hasStarted else { return }
        hasStarted = true
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didFinishLaunching = true }
        }
        // This marker and watchdog do not depend on SwiftUI reaching onAppear.
        // They diagnose LaunchServices/bootstrap failures rather than hanging CI.
        if let reportURL {
            let startup: [String: Any] = [
                "stage": "app-initialized",
                "processIdentifier": ProcessInfo.processInfo.processIdentifier,
                "bundlePath": Bundle.main.bundleURL.path,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: startup, options: [.sortedKeys]) {
                try? data.write(to: reportURL.appendingPathExtension("startup.json"), options: .atomic)
            }
        }
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline {
                if mainViewAppeared, let window = NSApp?.windows.first(where: {
                    $0.isVisible && $0.title == "Clicker" && !($0 is NSPanel)
                }), let content = window.contentView,
                   content.bounds.width >= 760, content.bounds.height >= 480 {
                    content.layoutSubtreeIfNeeded()
                    content.displayIfNeeded()
                    finish(window: window)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            finish(window: nil)
        }
    }

    func mainViewDidAppear() {
        mainViewAppeared = true
    }

    private func finish(window: NSWindow?) -> Never {
        let report: [String: Any] = [
            "status": window == nil ? "failed" : "passed",
            "safeMode": true,
            "globalInputServicesStarted": false,
            "mainViewAppeared": mainViewAppeared,
            "applicationDidFinishLaunching": didFinishLaunching,
            "activationPolicy": NSApp?.activationPolicy().rawValue ?? -1,
            "applicationIsRunning": NSApp?.isRunning ?? false,
            "applicationIsActive": NSApp?.isActive ?? false,
            "processIdentifier": ProcessInfo.processInfo.processIdentifier,
            "arguments": ProcessInfo.processInfo.arguments,
            "openFileRequest": UserDefaults.standard.stringArray(forKey: "NSOpen") ?? [],
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
            "bundlePath": Bundle.main.bundleURL.path,
            "sourceCommit": Bundle.main.object(forInfoDictionaryKey: "ClickerSourceCommit") as? String ?? "unknown",
            "windowTitle": window?.title ?? "",
            "contentWidth": window?.contentView?.bounds.width ?? 0,
            "contentHeight": window?.contentView?.bounds.height ?? 0,
            "observedWindows": (NSApp?.windows ?? []).map {
                ["title": $0.title, "visible": $0.isVisible,
                 "width": $0.contentView?.bounds.width ?? 0,
                 "height": $0.contentView?.bounds.height ?? 0] as [String: Any]
            },
        ]
        do {
            guard let reportURL else {
                throw CocoaError(.fileNoSuchFile)
            }
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: reportURL, options: .atomic)
        } catch {
            fputs("Smoke test could not write its report: \(error)\n", stderr)
            try? FileManager.default.removeItem(at: storeDirectory)
            exit(1)
        }
        // No stateful operation has started; terminating directly also gives the
        // shell a meaningful status for a failed native-window launch.
        try? FileManager.default.removeItem(at: storeDirectory)
        exit(window == nil ? 1 : 0)
    }
}

extension Notification.Name {
    /// 统一的控制通道：菜单栏、快捷键、UI 按钮都发这两个通知，由引擎层监听。
    static let toggleRecord = Notification.Name("clicker.toggleRecord")
    static let togglePlay = Notification.Name("clicker.togglePlay")
}
