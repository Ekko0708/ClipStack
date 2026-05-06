import AppKit

enum PasteUtils {
    /// 发送 ⌘V。部分系统版本需要「辅助功能」权限才能对外部 App 生效。
    static func simulateCommandV() {
        let src = CGEventSource(stateID: .hidSystemState)
            ?? CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 9 // kVK_ANSI_V
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
