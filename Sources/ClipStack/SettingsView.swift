import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle(
                    "启用快捷键（⌥␣）",
                    isOn: Binding(
                        get: { settings.hotkeyEnabled },
                        set: { settings.persistHotkeyEnabled($0) }
                    )
                )
                Text("关闭后仍可用菜单栏「打开历史」；设置变更后立即生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    "登录时启动",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.persistLaunchAtLogin($0) }
                    )
                )
                Text("部分系统版本需在「系统设置 → 通用 → 登录项」中允许 ClipStack。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, minHeight: 240)
        .padding()
    }
}
