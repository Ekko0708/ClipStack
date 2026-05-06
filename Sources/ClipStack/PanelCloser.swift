import AppKit

/// 让 SwiftUI 在需要时只关闭浮窗（⎋），或配合 controller 完成粘贴。
@MainActor
final class PanelCloser {
    static weak var controller: FloatingPanelController?

    static func register(_ c: FloatingPanelController) {
        controller = c
    }

    static func hideOnly() {
        controller?.hide()
    }
}
