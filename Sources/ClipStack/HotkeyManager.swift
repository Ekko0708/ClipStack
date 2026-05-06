import AppKit
import Carbon
import CHotkey

/// ⌥␣（或将 `requireControl` 设为 `true` 使用 ⌃⌥␣）。
enum HotkeyConfiguration {
    static let requireControl = false

    static func matches(_ event: NSEvent) -> Bool {
        guard event.isARepeat == false, event.keyCode == 49 else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.option),
              !flags.contains(.command),
              !flags.contains(.shift) else { return false }

        if requireControl {
            return flags.contains(.control)
        }
        return !flags.contains(.control)
    }
}

extension Notification.Name {
    static let clipStackNavigationKey = Notification.Name("clipStackNavigationKey")
}

fileprivate var clipStackCarbonFire: (() -> Void)?

fileprivate let clipStackCarbonC: @convention(c) () -> Void = {
    clipStackCarbonFire?()
}

/// Carbon 全局热键可关闭；面板方向键依赖 local `NSEvent`。
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onHotkey: (() -> Void)?

    weak var panelController: FloatingPanelController?

    private var localMonitor: Any?
    private var globalHotkeyFallback: Any?

    private var lastFireUptime: TimeInterval = 0
    private let fireLock = NSLock()

    private(set) var carbonHotkeyActive = false

    private init() {}

    /// 安装 **local** 方向键监听（与全局快捷键开关无关）。
    func installLocalNavigationMonitor() {
        if localMonitor != nil { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if let panel = self.panelController {
                let handled = self.invokeConsumeNavigation(panel: panel, event: event)
                if handled { return nil }
            }
            return event
        }
    }

    /// 按设置注册 / 注销全局 ⌥␣（Carbon + 可选 NSEvent 兜底）。
    func applyHotkeyEnabled(_ enabled: Bool) {
        cs_hotkey_unregister()
        clipStackCarbonFire = nil
        if let g = globalHotkeyFallback {
            NSEvent.removeMonitor(g)
            globalHotkeyFallback = nil
        }
        carbonHotkeyActive = false

        guard enabled else { return }

        clipStackCarbonFire = { [weak self] in
            guard let self else { return }
            self.handleHotkeyCandidate(uptime: ProcessInfo.processInfo.systemUptime)
        }

        let mods: UInt32 = HotkeyConfiguration.requireControl
            ? UInt32(optionKey | controlKey)
            : UInt32(optionKey)
        carbonHotkeyActive = cs_hotkey_register(mods, clipStackCarbonC) != 0

        if !carbonHotkeyActive {
            globalHotkeyFallback = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, HotkeyConfiguration.matches(event) else { return }
                let t = ProcessInfo.processInfo.systemUptime
                DispatchQueue.main.async {
                    self.handleHotkeyCandidate(uptime: t)
                }
            }
        }
    }

    func refreshGlobalHotkey() {
        let on = AppSettings.shared.hotkeyEnabled
        applyHotkeyEnabled(false)
        applyHotkeyEnabled(on)
    }

    func unregisterEverything() {
        applyHotkeyEnabled(false)
        if let l = localMonitor {
            NSEvent.removeMonitor(l)
            localMonitor = nil
        }
    }

    var isGlobalMonitorActive: Bool {
        carbonHotkeyActive || globalHotkeyFallback != nil
    }

    private func handleHotkeyCandidate(uptime: TimeInterval) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.handleHotkeyCandidate(uptime: uptime)
            }
            return
        }
        guard AppSettings.shared.hotkeyEnabled else { return }
        fireLock.lock()
        defer { fireLock.unlock() }
        guard uptime - lastFireUptime > 0.2 else { return }
        lastFireUptime = uptime
        onHotkey?()
    }

    private func invokeConsumeNavigation(panel: FloatingPanelController, event: NSEvent) -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                panel.consumeNavigationKey(event)
            }
        }
        var handled = false
        DispatchQueue.main.sync {
            handled = MainActor.assumeIsolated {
                panel.consumeNavigationKey(event)
            }
        }
        return handled
    }
}
