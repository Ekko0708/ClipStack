import AppKit
import Combine
import SwiftUI

@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var favorites: [HistoryEntry] = []

    private var lastChangeCount: Int
    private var timer: Timer?
    private var suppressNextSample = false

    let maxEntries = 80

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
        loadFavorites()
    }

    func loadFavorites() {
        favorites = FavoritePersistence.load().compactMap { FavoritePersistence.decode($0) }
    }

    private func saveFavorites() {
        let dtos = favorites.map { FavoritePersistence.encode(entry: $0, savedAt: $0.capturedAt) }
        FavoritePersistence.save(dtos)
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    deinit {
        timer?.invalidate()
    }

    func tick() {
        let pb = NSPasteboard.general
        if suppressNextSample {
            suppressNextSample = false
            lastChangeCount = pb.changeCount
            return
        }
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard let entry = HistoryEntry.capture(from: pb) else { return }
        if let first = entries.first, first.isDuplicate(of: entry) { return }
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    func applyToSystemPasteboard(_ entry: HistoryEntry) {
        suppressNextSample = true
        entry.restore(to: NSPasteboard.general)
        lastChangeCount = NSPasteboard.general.changeCount
    }

    /// 从浮窗选定一项并粘贴后，将其视为当前「最新复制」，顶到历史第一条。
    func promotePickedEntryToTop(_ entry: HistoryEntry) {
        let top = entry.refreshedAsLatestCopy()
        entries.removeAll { $0.id == entry.id || $0.isDuplicate(of: entry) }
        entries.insert(top, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    func remove(at index: Int) {
        guard entries.indices.contains(index) else { return }
        entries.remove(at: index)
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func clear() {
        entries.removeAll()
    }

    func toggleFavorite(_ entry: HistoryEntry) {
        if let idx = favorites.firstIndex(where: { $0.isDuplicate(of: entry) }) {
            favorites.remove(at: idx)
        } else {
            favorites.insert(entry.cloneForFavorite(), at: 0)
        }
        saveFavorites()
    }

    func isFavorite(_ entry: HistoryEntry) -> Bool {
        favorites.contains { $0.isDuplicate(of: entry) }
    }

    func removeFavorite(id: UUID) {
        favorites.removeAll { $0.id == id }
        saveFavorites()
    }

    func clearFavorites() {
        favorites.removeAll()
        saveFavorites()
    }
}
