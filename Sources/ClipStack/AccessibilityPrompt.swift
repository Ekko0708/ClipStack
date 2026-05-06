import ApplicationServices

/// 全局快捷键依赖「辅助功能」：未授权时 `addGlobalMonitorForEvents` 往往为 `nil`，在其他 App 前台无法收到 ⌥␣。
enum AccessibilityPrompt {
    /// 若未授权，会弹出系统对话框引导打开「隐私与安全性 → 辅助功能」。
    @discardableResult
    static func requestTrustPrompt() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts: [String: Bool] = [key: true]
        return AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }
}
