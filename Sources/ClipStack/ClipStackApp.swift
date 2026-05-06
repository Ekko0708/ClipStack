import AppKit
import SwiftUI

@main
struct ClipStackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("ClipStack", systemImage: "doc.on.clipboard") {
            MenuBarExtraCommands(appDelegate: appDelegate)
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - 菜单（设置需手动激活 App，否则设置窗在 accessory 形态下不会到台前）

private struct MenuBarExtraCommands: View {
    let appDelegate: AppDelegate

    var body: some View {
        Button("打开历史 (⌥␣)") {
            appDelegate.togglePanel()
        }
        Button {
            appDelegate.openSettingsWindow()
        } label: {
            Label("设置…", systemImage: "gearshape")
        }
        Divider()
        Button("打开「辅助功能」设置…") {
            appDelegate.openAccessibilitySettings()
        }
        Button("刷新快捷键监听") {
            appDelegate.reregisterHotkeys()
        }
        Divider()
        Button("清空历史记录") {
            appDelegate.clearHistory()
        }
        Button("清空收藏") {
            appDelegate.clearFavorites()
        }
        Button("退出") {
            NSApp.terminate(nil)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let clipboard = ClipboardMonitor()
    private var panel: FloatingPanelController!
    private var trustRecheck: Timer?
    private var trustPollCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = AccessibilityPrompt.requestTrustPrompt()

        AppSettings.shared.reconcileLaunchAtLoginWithServiceManagement()

        panel = FloatingPanelController(clipboard: clipboard)
        PanelCloser.register(panel)
        clipboard.start()

        HotkeyManager.shared.panelController = panel
        HotkeyManager.shared.onHotkey = { [weak self] in
            self?.panel.toggle()
        }
        HotkeyManager.shared.installLocalNavigationMonitor()
        HotkeyManager.shared.applyHotkeyEnabled(AppSettings.shared.hotkeyEnabled)

        trustRecheck?.invalidate()
        trustPollCount = 0
        trustRecheck = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] t in
            guard let self else {
                t.invalidate()
                return
            }
            Task { @MainActor in
                self.handleTrustPollTick(timer: t)
            }
        }
        if let trustRecheck {
            RunLoop.main.add(trustRecheck, forMode: .common)
        }
    }

    func bringSettingsWindowsForward() {
        NSApp.activate(ignoringOtherApps: true)
        let candidates = NSApp.windows.filter { w in
            w.isVisible && w.canBecomeKey && !w.isFloatingPanel
        }
        if let key = candidates.first(where: { $0.isKeyWindow }) ?? candidates.last {
            key.makeKeyAndOrderFront(nil)
        }
    }

    private func handleTrustPollTick(timer: Timer) {
        trustPollCount += 1
        if AccessibilityPrompt.isTrusted || trustPollCount >= 20 {
            HotkeyManager.shared.refreshGlobalHotkey()
        }
        if trustPollCount >= 20 {
            timer.invalidate()
            trustRecheck = nil
        }
    }

    func togglePanel() {
        panel.toggle()
    }

    /// macOS 13+：不依赖 `@Environment(\.openSettings)`（仅 14+ 可用）。
    func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let showSettings = Selector(("showSettingsWindow:"))
        let showPrefs = Selector(("showPreferencesWindow:"))
        if NSApp.responds(to: showSettings) {
            NSApp.sendAction(showSettings, to: nil, from: nil)
        } else if NSApp.responds(to: showPrefs) {
            NSApp.sendAction(showPrefs, to: nil, from: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.bringSettingsWindowsForward()
        }
    }

    func clearHistory() {
        clipboard.clear()
    }

    func clearFavorites() {
        clipboard.clearFavorites()
    }

    func openAccessibilitySettings() {
        let s = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let u = URL(string: s) {
            NSWorkspace.shared.open(u)
        }
    }

    func reregisterHotkeys() {
        HotkeyManager.shared.refreshGlobalHotkey()
    }
}
