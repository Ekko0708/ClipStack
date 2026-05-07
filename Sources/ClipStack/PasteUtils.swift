import AppKit

enum PasteUtils {
    /// 发送 ⌘V。需要「辅助功能」权限才能稳定对外部 App 生效。
    /// - 用 `.combinedSessionState`（而非 `.hidSystemState`），避免把用户当前物理按下的键
    ///   （比如刚刚的 Enter / 残留的 Option）混进合成事件里。
    /// - down/up 之间留 8ms，给系统充分时间把 Cmd+V 路由到目标窗口。
    static func simulateCommandV() {
        guard AXIsProcessTrusted() else {
            // 重建 / 重新签名后 TCC 授权会失效，是这里最常见的失败原因。
            DebugLog.t("cgEvent", "skip: accessibility not trusted")
            return
        }

        let src = CGEventSource(stateID: .combinedSessionState)
            ?? CGEventSource(stateID: .privateState)
        let v: CGKeyCode = 9 // kVK_ANSI_V

        guard let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false) else {
            DebugLog.t("cgEvent", "fail: cannot create CGEvent")
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        usleep(8_000)
        up.post(tap: .cghidEventTap)
    }
}
