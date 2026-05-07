import Foundation
import AppKit

/// 写文件 + NSLog 的双通道诊断日志。
/// - 路径：`~/Library/Logs/ClipStack/runtime.log`（按天截断）。
/// - unified log 偶尔会吞掉 `NSLog` 的 stderr 输出，文件日志能保证一份是肉眼可见的。
enum DebugLog {
    private static let queue = DispatchQueue(label: "com.clipstack.debug.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private static let logURL: URL? = {
        let fm = FileManager.default
        guard let base = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Logs/ClipStack", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return dir.appendingPathComponent("runtime.log")
    }()

    static func t(_ tag: String, _ message: @autoclosure () -> String = "") {
        let m = message()
        let line: String = {
            let now = formatter.string(from: Date())
            if m.isEmpty {
                return "\(now) [\(tag)]\n"
            }
            return "\(now) [\(tag)] \(m)\n"
        }()
        NSLog("[ClipStack] %@ %@", tag, m)
        guard let url = logURL else { return }
        queue.async {
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: url.path) {
                    if let h = try? FileHandle(forWritingTo: url) {
                        defer { try? h.close() }
                        _ = try? h.seekToEnd()
                        try? h.write(contentsOf: data)
                    }
                } else {
                    try? data.write(to: url, options: .atomic)
                }
            }
        }
    }

    /// 给文件里写一条「会话开始」标记，方便分隔多次启动。
    static func sessionStart(_ note: String) {
        t("BOOT", "===== \(note) =====")
    }

    static var logFilePath: String? { logURL?.path }
}
