import AppKit
import AVFoundation

struct HistoryEntry: Identifiable, Equatable {
    enum DisplayMode: Equatable {
        case compactText
        case visual
    }

    enum ContentCategory: String, Codable, CaseIterable, Identifiable {
        case text
        case image
        case video
        case file
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .text: return "文本"
            case .image: return "图片"
            case .video: return "视频"
            case .file: return "文件"
            case .other: return "其它"
            }
        }
    }

    let id: UUID
    let capturedAt: Date
    /// 与 `NSPasteboard` 快照一致，供持久化与还原。
    let itemData: [[(String, Data)]]

    let displayMode: DisplayMode
    let textPreview: String?
    let thumbnail: NSImage?
    let timeCaption: String
    let titleLine: String
    let iconSystemName: String
    let category: ContentCategory

    private enum ThumbnailOrigin {
        case none
        case bitmap
        case videoFile
    }

    static func capture(from pasteboard: NSPasteboard) -> HistoryEntry? {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return nil }
        var snapshot: [[(String, Data)]] = []
        for item in items {
            var pairs: [(String, Data)] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    pairs.append((type.rawValue, data))
                }
            }
            if !pairs.isEmpty { snapshot.append(pairs) }
        }
        return makeFromSnapshot(snapshot, capturedAt: Date(), id: nil)
    }

    /// 从持久化层还原。
    static func fromSnapshot(_ snapshot: [[(String, Data)]], capturedAt: Date, id: UUID, category: ContentCategory) -> HistoryEntry? {
        makeFromSnapshot(snapshot, capturedAt: capturedAt, id: id, categoryHint: category)
    }

    private static func makeFromSnapshot(
        _ snapshot: [[(String, Data)]],
        capturedAt: Date,
        id: UUID?,
        categoryHint: ContentCategory? = nil
    ) -> HistoryEntry? {
        guard !snapshot.isEmpty else { return nil }

        let eid = id ?? UUID()
        let time = formatTime(capturedAt)
        let plain = firstPlainText(in: snapshot)
        var thumb: NSImage?
        var thumbOrigin: ThumbnailOrigin = .none
        thumb = decodeThumbnail(from: snapshot)
        if thumb != nil { thumbOrigin = .bitmap }

        let fileUrls = fileURLs(in: snapshot)
        if thumb == nil, let videoURL = fileUrls.first(where: { isVideoURL($0) }) {
            thumb = thumbnailForVideoFile(at: videoURL)
            if thumb != nil { thumbOrigin = .videoFile }
        }

        if let thumb {
            let hasVid = fileUrls.contains(where: { isVideoURL($0) }) || thumbOrigin == .videoFile
            // Finder 复制 PDF 等文件时常带 JPEG/PNG 预览，此前会先走「缩略图」分支并标成「图片」，在「文件」分类里就看不到。
            let fileLikeBecauseHint = categoryHint == .file
            let fileLikeBecauseURLs = !fileUrls.isEmpty && !hasVid && fileUrls.contains(where: { !isRasterImageFileURL($0) })
            if fileLikeBecauseHint || fileLikeBecauseURLs {
                let names = fileNamePreview(in: snapshot) ?? "文件"
                let icon = fileUrls.count == 1 ? "doc.fill" : "folder"
                return HistoryEntry(
                    id: eid,
                    capturedAt: capturedAt,
                    itemData: snapshot,
                    displayMode: .visual,
                    textPreview: nil,
                    thumbnail: thumb,
                    timeCaption: time,
                    titleLine: names,
                    iconSystemName: icon,
                    category: .file
                )
            }

            let headline: String
            if let plain {
                let t = plain.trimmingCharacters(in: .whitespacesAndNewlines)
                headline = shortHeadline(from: t, limit: 72)
            } else if let name = fileUrls.first?.lastPathComponent, !name.isEmpty {
                headline = name
            } else {
                headline = "图片"
            }
            let icon = hasVid ? "film" : "photo"
            let cat: ContentCategory = categoryHint ?? (hasVid ? .video : .image)
            return HistoryEntry(
                id: eid,
                capturedAt: capturedAt,
                itemData: snapshot,
                displayMode: .visual,
                textPreview: nil,
                thumbnail: thumb,
                timeCaption: time,
                titleLine: headline,
                iconSystemName: icon,
                category: cat
            )
        }

        if let plain {
            let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = trimmed.isEmpty ? "空白文本" : clipText(trimmed, maxChars: 12_000)
            let cat = categoryHint ?? .text
            return HistoryEntry(
                id: eid,
                capturedAt: capturedAt,
                itemData: snapshot,
                displayMode: .compactText,
                textPreview: body,
                thumbnail: nil,
                timeCaption: time,
                titleLine: "",
                iconSystemName: "doc.text",
                category: cat
            )
        }

        if !fileUrls.isEmpty {
            let names = fileNamePreview(in: snapshot) ?? "文件"
            let hasVid = fileUrls.contains(where: { isVideoURL($0) })
            let cat = categoryHint ?? (hasVid ? .video : .file)
            return HistoryEntry(
                id: eid,
                capturedAt: capturedAt,
                itemData: snapshot,
                displayMode: .visual,
                textPreview: nil,
                thumbnail: nil,
                timeCaption: time,
                titleLine: names,
                iconSystemName: hasVid ? "film" : "folder",
                category: cat
            )
        }

        if let html = firstHTMLSnippet(in: snapshot) {
            let cat = categoryHint ?? .text
            return HistoryEntry(
                id: eid,
                capturedAt: capturedAt,
                itemData: snapshot,
                displayMode: .compactText,
                textPreview: html,
                thumbnail: nil,
                timeCaption: time,
                titleLine: "",
                iconSystemName: "doc.richtext",
                category: cat
            )
        }

        let cat = categoryHint ?? .other
        return HistoryEntry(
            id: eid,
            capturedAt: capturedAt,
            itemData: snapshot,
            displayMode: .visual,
            textPreview: nil,
            thumbnail: nil,
            timeCaption: time,
            titleLine: "富文本 / 其他",
            iconSystemName: "doc.richtext",
            category: cat
        )
    }

    func matchesSearch(_ query: String) -> Bool {
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        if titleLine.localizedCaseInsensitiveContains(t) { return true }
        if let tp = textPreview, tp.localizedCaseInsensitiveContains(t) { return true }
        if category.title.localizedCaseInsensitiveContains(t) { return true }
        return false
    }

    func cloneForFavorite() -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            capturedAt: Date(),
            itemData: itemData,
            displayMode: displayMode,
            textPreview: textPreview,
            thumbnail: thumbnail,
            timeCaption: Self.formatTime(Date()),
            titleLine: titleLine,
            iconSystemName: iconSystemName,
            category: category
        )
    }

    /// 写入剪贴板后作为「最新一条」插回列表顶部时使用，刷新时间与展示文案。
    func refreshedAsLatestCopy(now: Date = Date()) -> HistoryEntry {
        HistoryEntry(
            id: id,
            capturedAt: now,
            itemData: itemData,
            displayMode: displayMode,
            textPreview: textPreview,
            thumbnail: thumbnail,
            timeCaption: Self.formatTime(now),
            titleLine: titleLine,
            iconSystemName: iconSystemName,
            category: category
        )
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        var objects: [NSPasteboardItem] = []
        for pairs in itemData {
            let item = NSPasteboardItem()
            for (typeStr, data) in pairs {
                item.setData(data, forType: NSPasteboard.PasteboardType(typeStr))
            }
            objects.append(item)
        }
        pasteboard.writeObjects(objects)
    }

    func isDuplicate(of other: HistoryEntry) -> Bool {
        if itemData.count != other.itemData.count { return false }
        for (left, right) in zip(itemData, other.itemData) {
            if left.count != right.count { return false }
            for (a, b) in zip(left, right) {
                if a.0 != b.0 || a.1 != b.1 { return false }
            }
        }
        return true
    }

    static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
        lhs.id == rhs.id
    }

    fileprivate static func formatTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }

    private static func clipText(_ s: String, maxChars: Int) -> String {
        guard s.count > maxChars else { return s }
        let idx = s.index(s.startIndex, offsetBy: maxChars)
        return String(s[..<idx]) + "…"
    }

    private static func shortHeadline(from text: String, limit: Int) -> String {
        let oneLine = text.split(separator: "\n", maxSplits: 1).map(String.init).first ?? text
        let t = oneLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= limit { return t }
        return String(t.prefix(limit)) + "…"
    }

    private static func decodeThumbnail(from snapshot: [[(String, Data)]]) -> NSImage? {
        let imageTypes: Set<String> = [
            NSPasteboard.PasteboardType.png.rawValue,
            "public.png",
            NSPasteboard.PasteboardType.tiff.rawValue,
            "public.tiff",
            "public.jpeg",
            "public.jpg",
            "public.heic",
            "com.compuserve.gif"
        ]

        for group in snapshot {
            for (ut, data) in group {
                guard data.count <= 24_000_000 else { continue }
                guard imageTypes.contains(ut) || ut.contains("image") else { continue }
                guard let img = NSImage(data: data) else { continue }
                return downsample(img, max: 160)
            }
        }
        return nil
    }

    private static func downsample(_ image: NSImage, max side: CGFloat) -> NSImage {
        let s = image.size
        guard s.width > 0, s.height > 0 else { return image }
        let scale = min(1, min(side / s.width, side / s.height))
        guard scale < 1 else { return image }
        let target = NSSize(width: floor(s.width * scale), height: floor(s.height * scale))
        let img = NSImage(size: target)
        img.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target), from: NSRect(origin: .zero, size: s), operation: .copy, fraction: 1)
        img.unlockFocus()
        return img
    }

    private static func firstPlainText(in snapshot: [[(String, Data)]]) -> String? {
        for group in snapshot {
            for (ut, data) in group {
                if ut == "public.utf8-plain-text" || ut == "public/plain-text" || ut == NSPasteboard.PasteboardType.string.rawValue,
                   let s = String(data: data, encoding: .utf8) {
                    return s
                }
            }
        }
        return nil
    }

    private static func firstHTMLSnippet(in snapshot: [[(String, Data)]]) -> String? {
        for group in snapshot {
            for (ut, data) in group {
                if ut == "public.html", let s = String(data: data, encoding: .utf8) {
                    let t = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    let c = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !c.isEmpty else { return nil }
                    return clipText(c, maxChars: 12_000)
                }
            }
        }
        return nil
    }

    private static func fileNamePreview(in snapshot: [[(String, Data)]]) -> String? {
        let urls = fileURLs(in: snapshot)
        guard !urls.isEmpty else { return nil }
        let names = urls.map(\.lastPathComponent).prefix(3)
        let joined = names.joined(separator: ", ")
        return urls.count > 3 ? joined + "…" : joined
    }

    private static func fileURLs(in snapshot: [[(String, Data)]]) -> [URL] {
        let fileURLType = NSPasteboard.PasteboardType.fileURL.rawValue
        let namesType = NSPasteboard.PasteboardType("NSFilenamesPboardType").rawValue
        var urls: [URL] = []
        for group in snapshot {
            for (ut, data) in group {
                if ut == "public.file-url" || ut == fileURLType {
                    guard let s = decodeFileURLString(from: data), let u = URL(string: s) else { continue }
                    urls.append(u)
                    continue
                }
                if ut == namesType || ut == "NSFilenamesPboardType" {
                    if let paths = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String] {
                        for p in paths {
                            urls.append(URL(fileURLWithPath: p))
                        }
                    }
                }
            }
        }
        return dedupeFileURLsPreservingOrder(urls)
    }

    /// 纯图片扩展名（从 Finder 复制的 .jpg 等仍可在「图片」里展示）；PDF / 文档等归入「文件」。
    private static func isRasterImageFileURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let exts = ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp", "ico"]
        return exts.contains(url.pathExtension.lowercased())
    }

    private static func decodeFileURLString(from data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let s = String(data: data, encoding: .utf16) { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }

    private static func dedupeFileURLsPreservingOrder(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        for u in urls {
            let k = u.standardizedFileURL.path
            if seen.insert(k).inserted { out.append(u) }
        }
        return out
    }

    private static func isVideoURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let exts = ["mp4", "mov", "m4v", "webm", "mkv", "avi", "mpeg", "mpg"]
        return exts.contains(url.pathExtension.lowercased())
    }

    private static func thumbnailForVideoFile(at url: URL) -> NSImage? {
        guard isVideoURL(url) else { return nil }
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        let t = CMTime(seconds: 0.15, preferredTimescale: 600)
        do {
            var actual = CMTime.zero
            let cgImage = try gen.copyCGImage(at: t, actualTime: &actual)
            let img = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            return downsample(img, max: 160)
        } catch {
            return nil
        }
    }
}
