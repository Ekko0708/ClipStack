import AppKit
import Foundation

/// 收藏夹磁盘存储（Application Support/ClipStack/favorites.json）。
enum FavoritePersistence {
    struct DTO: Codable {
        let id: UUID
        let savedAt: Date
        let category: String
        /// 与 `HistoryEntry` 的 itemData 对应：每项为若干 type → base64 数据。
        let items: [[[String: String]]]
    }

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("ClipStack", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return dir.appendingPathComponent("favorites.json")
    }

    static func load() -> [DTO] {
        guard let url = fileURL else { return [] }
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([DTO].self, from: data)) ?? []
    }

    static func save(_ dtos: [DTO]) {
        guard let url = fileURL else { return }
        guard let data = try? JSONEncoder().encode(dtos) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func encode(entry: HistoryEntry, savedAt: Date) -> DTO {
        let layers: [[[String: String]]] = entry.itemData.map { pairs in
            pairs.map { t, d in ["t": t, "d": d.base64EncodedString()] }
        }
        return DTO(id: entry.id, savedAt: savedAt, category: entry.category.rawValue, items: layers)
    }

    static func decode(_ dto: DTO) -> HistoryEntry? {
        guard let cat = HistoryEntry.ContentCategory(rawValue: dto.category) else { return nil }
        var snapshot: [[(String, Data)]] = []
        for item in dto.items {
            var pairs: [(String, Data)] = []
            for dict in item {
                guard let t = dict["t"], let b64 = dict["d"],
                      let data = Data(base64Encoded: b64) else { continue }
                pairs.append((t, data))
            }
            if !pairs.isEmpty { snapshot.append(pairs) }
        }
        guard !snapshot.isEmpty else { return nil }
        return HistoryEntry.fromSnapshot(snapshot, capturedAt: dto.savedAt, id: dto.id, category: cat)
    }
}
