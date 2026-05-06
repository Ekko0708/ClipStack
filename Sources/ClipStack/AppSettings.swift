import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let hotkeyKey = "ClipStack.hotkeyEnabled"
    private let loginKey = "ClipStack.launchAtLogin"

    @Published private(set) var hotkeyEnabled: Bool
    @Published private(set) var launchAtLogin: Bool

    private init() {
        hotkeyEnabled = UserDefaults.standard.object(forKey: hotkeyKey) as? Bool ?? true
        launchAtLogin = UserDefaults.standard.object(forKey: loginKey) as? Bool ?? false
    }

    func persistHotkeyEnabled(_ value: Bool) {
        hotkeyEnabled = value
        UserDefaults.standard.set(value, forKey: hotkeyKey)
        HotkeyManager.shared.applyHotkeyEnabled(value)
    }

    func persistLaunchAtLogin(_ value: Bool) {
        launchAtLogin = value
        UserDefaults.standard.set(value, forKey: loginKey)
        let sm = SMAppService.mainApp
        do {
            if value {
                try sm.register()
            } else {
                try sm.unregister()
            }
        } catch {}
    }

    /// 启动后对照系统登录项状态修正开关（可选）。
    func reconcileLaunchAtLoginWithServiceManagement() {
        let sm = SMAppService.mainApp
        switch sm.status {
        case .enabled:
            if !launchAtLogin {
                launchAtLogin = true
                UserDefaults.standard.set(true, forKey: loginKey)
            }
        default:
            break
        }
    }
}
