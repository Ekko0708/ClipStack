import AppKit
import SwiftUI

private final class PickBridge {
    weak var owner: FloatingPanelController?
}

/// 每次打开浮窗递增，用于重置键盘选中行。
@MainActor
final class PanelSession: ObservableObject {
    @Published private(set) var generation: Int = 0

    func markOpened() {
        generation &+= 1
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let hosting: NSHostingController<HistoryPanelView>
    private let panel: KeyablePanel
    private let clipboard: ClipboardMonitor
    let session = PanelSession()

    private var appBeforePanel: NSRunningApplication?
    private var isShown = false
    private var resignIgnoreUntil: Date = .distantPast
    private var outsideClickMonitor: Any?

    init(clipboard: ClipboardMonitor) {
        self.clipboard = clipboard

        let bridge = PickBridge()
        let hv = HistoryPanelView(clipboard: clipboard, session: session) { entry in
            bridge.owner?.pasteEntry(entry)
        }
        hosting = NSHostingController(rootView: hv)

        let w = NSSize(width: 432, height: 556)
        panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: w),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()

        bridge.owner = self
        panel.delegate = self

        panel.contentViewController = hosting
        panel.setContentSize(w)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        if let cv = panel.contentView {
            cv.wantsLayer = true
            cv.layer?.cornerRadius = 18
            cv.layer?.masksToBounds = true
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        guard isShown, Date() > resignIgnoreUntil else { return }
        hide(immediate: true)
    }

    /// 由 `HotkeyManager` 的 local monitor 调用；返回 `true` 表示事件已处理。
    func consumeNavigationKey(_ event: NSEvent) -> Bool {
        guard isShown else { return false }
        let code = Int(event.keyCode)
        // Tab：从搜索框退出焦点，恢复 ←→ 切换分类
        if code == 48, textInputIsFirstResponder(in: panel) {
            panel.makeFirstResponder(hosting.view)
            return true
        }
        // 文本框内：左右移动光标、Delete / Forward Delete 必须交给输入框。
        if code == 123 || code == 124 || code == 51 || code == 117,
           textInputIsFirstResponder(in: panel) {
            return false
        }
        switch code {
        case 125, 126, 123, 124, 36, 76, 53, 51, 117:
            // 同步在 monitor 里 paste/hide 会与当前 keyDown 处理重入，导致偶发不粘贴；延后到下一轮 run loop。
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .clipStackNavigationKey, object: code)
            }
            return true
        default:
            return false
        }
    }

    /// 只认 AppKit 原生文本控件，避免 SwiftUI 视图类名里带 “Text…” 子串误伤方向键 / 分类切换。
    private func textInputIsFirstResponder(in window: NSWindow?) -> Bool {
        var r: NSResponder? = window?.firstResponder
        while let cur = r {
            if cur is NSTextView || cur is NSTextField { return true }
            r = cur.nextResponder
        }
        return false
    }

    func toggle() {
        if isShown {
            hide(immediate: true)
        } else {
            show()
        }
    }

    func show() {
        if isShown { return }
        isShown = true
        session.markOpened()

        appBeforePanel = NSWorkspace.shared.frontmostApplication
        resignIgnoreUntil = Date().addingTimeInterval(0.28)

        positionNearCursor()
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        scheduleOutsideClickMonitor()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel.makeFirstResponder(self.hosting.view)
        }
    }

    func pasteEntry(_ entry: HistoryEntry) {
        clipboard.applyToSystemPasteboard(entry)
        clipboard.promotePickedEntryToTop(entry)

        let target = appBeforePanel
        hide(immediate: true)

        let ours = Bundle.main.bundleIdentifier
        if let target, let ours, target.bundleIdentifier == ours {
            PasteUtils.simulateCommandV()
            return
        }
        if let target {
            target.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                PasteUtils.simulateCommandV()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                PasteUtils.simulateCommandV()
            }
        }
    }

    func hide(immediate: Bool = true) {
        let wasShown = isShown
        isShown = false
        removeOutsideClickMonitor()

        if !wasShown {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }

        if immediate {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.09
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
            self?.panel.alphaValue = 1
        })
    }

    private func scheduleOutsideClickMonitor() {
        removeOutsideClickMonitor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            guard let self, self.isShown else { return }
            self.installOutsideClickMonitor()
        }
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.isShown else { return }
            let p = NSEvent.mouseLocation
            if self.panel.frame.contains(p) { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isShown else { return }
                let q = NSEvent.mouseLocation
                if self.panel.frame.contains(q) { return }
                self.hide(immediate: true)
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
    }

    private func positionNearCursor() {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else {
            panel.center()
            return
        }
        let mouse = NSEvent.mouseLocation
        var origin = CGPoint(x: mouse.x - panel.frame.width / 2, y: mouse.y - panel.frame.height - 18)
        let margin: CGFloat = 14
        let sf = screen.visibleFrame
        origin.x = min(max(origin.x, sf.minX + margin), sf.maxX - panel.frame.width - margin)
        origin.y = min(max(origin.y, sf.minY + margin), sf.maxY - panel.frame.height - margin)
        panel.setFrameTopLeftPoint(NSPoint(x: origin.x, y: origin.y + panel.frame.height))
    }
}

// MARK: - SwiftUI

private enum HistoryFilterSegment: String, CaseIterable, Identifiable {
    case all
    case text
    case image
    case video
    case file
    case favorite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .video: return "视频"
        case .file: return "文件"
        case .favorite: return "收藏"
        }
    }
}

struct HistoryPanelView: View {
    @ObservedObject var clipboard: ClipboardMonitor
    @ObservedObject var session: PanelSession
    var onPick: (HistoryEntry) -> Void

    @State private var selectedIndex: Int = 0
    @State private var filter: HistoryFilterSegment = .all
    @State private var searchText: String = ""

    private var tinyVersionLabel: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        if short.isEmpty, build.isEmpty { return "" }
        if build.isEmpty { return short }
        return "\(short) (\(build))"
    }

    private var visibleEntries: [HistoryEntry] {
        let base: [HistoryEntry]
        switch filter {
        case .all: base = clipboard.entries
        case .text: base = clipboard.entries.filter { $0.category == .text }
        case .image: base = clipboard.entries.filter { $0.category == .image }
        case .video: base = clipboard.entries.filter { $0.category == .video }
        case .file: base = clipboard.entries.filter { $0.category == .file }
        case .favorite: base = clipboard.favorites
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return base }
        return base.filter { $0.matchesSearch(q) }
    }

    private var emptyTitle: String {
        if filter == .favorite, clipboard.favorites.isEmpty { return "暂无收藏" }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, visibleEntries.isEmpty {
            return "无匹配结果"
        }
        if visibleEntries.isEmpty { return "暂无内容" }
        return ""
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            searchField
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)

            if visibleEntries.isEmpty {
                emptyState
            } else {
                entryScroll
            }

            footer
        }
        .frame(width: 432, height: 556)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.plusLighter)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.38), radius: 28, y: 14)
        .onReceive(NotificationCenter.default.publisher(for: .clipStackNavigationKey)) { note in
            guard let code = note.object as? Int else { return }
            switch code {
            case 126: moveSelection(-1)
            case 125: moveSelection(1)
            case 123: moveFilter(-1)
            case 124: moveFilter(1)
            case 36, 76: confirmSelection()
            case 53: PanelCloser.hideOnly()
            case 51, 117: deleteSelection()
            default: break
            }
        }
        .onAppear {
            clampSelection()
        }
        .onChange(of: session.generation) { _ in
            selectedIndex = 0
            searchText = ""
            clampSelection()
        }
        .onChange(of: clipboard.entries.count) { _ in
            clampSelection()
        }
        .onChange(of: clipboard.favorites.count) { _ in
            clampSelection()
        }
        .onChange(of: filter) { _ in
            selectedIndex = 0
            clampSelection()
        }
        .onChange(of: searchText) { _ in
            selectedIndex = 0
            clampSelection()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(nsColor: .labelColor).opacity(0.78))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if !tinyVersionLabel.isEmpty {
                Text(tinyVersionLabel)
                    .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary.opacity(0.9))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(HistoryFilterSegment.allCases) { seg in
                    filterChip(seg)
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 6)
    }

    private func filterChip(_ seg: HistoryFilterSegment) -> some View {
        let on = filter == seg
        return Button {
            filter = seg
        } label: {
            Text(seg.title)
                .font(.system(size: 11, weight: on ? .semibold : .regular))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(on ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("搜索关键词…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var entryScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                        HistoryRow(
                            entry: entry,
                            isSelected: index == selectedIndex,
                            isFavorite: filter == .favorite ? true : clipboard.isFavorite(entry),
                            onToggleFavorite: {
                                clipboard.toggleFavorite(entry)
                            }
                        )
                        .id(entry.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedIndex = index
                        }
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                selectedIndex = index
                                onPick(entry)
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedIndex) { newIdx in
                guard visibleEntries.indices.contains(newIdx) else { return }
                let id = visibleEntries[newIdx].id
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "square.dashed")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text(emptyTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("←→ 分类 · ↑↓ 条目 · Tab 退出搜索 · ↩ 粘贴 · ⎋ 关闭")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            if filter == .favorite {
                Button("清空收藏") {
                    clipboard.clearFavorites()
                    selectedIndex = 0
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            } else {
                Button("清空记录") {
                    clipboard.clear()
                    selectedIndex = 0
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.05))
    }

    private func moveFilter(_ delta: Int) {
        let segments = HistoryFilterSegment.allCases
        guard let i = segments.firstIndex(of: filter) else { return }
        let n = segments.count
        let j = ((i + delta) % n + n) % n
        filter = segments[j]
    }

    private func clampSelection() {
        guard !visibleEntries.isEmpty else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(0, selectedIndex), visibleEntries.count - 1)
    }

    private func moveSelection(_ delta: Int) {
        guard !visibleEntries.isEmpty else { return }
        let n = visibleEntries.count
        selectedIndex = min(max(0, selectedIndex + delta), n - 1)
    }

    private func confirmSelection() {
        guard visibleEntries.indices.contains(selectedIndex) else { return }
        onPick(visibleEntries[selectedIndex])
    }

    private func deleteSelection() {
        guard visibleEntries.indices.contains(selectedIndex) else { return }
        let entry = visibleEntries[selectedIndex]
        if filter == .favorite {
            clipboard.removeFavorite(id: entry.id)
        } else if let idx = clipboard.entries.firstIndex(where: { $0.id == entry.id }) {
            clipboard.remove(at: idx)
        }
        clampSelection()
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    var isSelected: Bool
    var isFavorite: Bool
    var onToggleFavorite: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Group {
                switch entry.displayMode {
                case .compactText:
                    compactTextRow
                case .visual:
                    visualRow
                }
            }
            .padding(entry.displayMode == .compactText ? EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 4) : EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 4))

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 15))
                    .foregroundStyle(isFavorite ? Color.orange : Color.secondary.opacity(0.7))
                    .frame(width: 32, height: 36)
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "取消收藏" : "加入收藏（永久保留）")
        }
        .background {
            RoundedRectangle(cornerRadius: entry.displayMode == .compactText ? 10 : 13, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.18)
                        : Color.primary.opacity(0.045)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: entry.displayMode == .compactText ? 10 : 13, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.45) : Color.clear,
                    lineWidth: 1
                )
        }
    }

    private var compactTextRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.textPreview ?? "")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.timeCaption)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var visualRow: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                if let img = entry.thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    Image(systemName: entry.iconSystemName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.titleLine)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(entry.timeCaption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}
