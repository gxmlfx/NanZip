import Foundation

public struct ArchiveItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let path: String
    public let size: Int64
    public let modifiedAt: Date?
    public let isDirectory: Bool
    public let isSymlink: Bool

    public init(
        id: UUID = UUID(),
        path: String,
        size: Int64,
        modifiedAt: Date?,
        isDirectory: Bool,
        isSymlink: Bool = false
    ) {
        self.id = id
        self.path = path
        self.size = size
        self.modifiedAt = modifiedAt
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
    }

    public var name: String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return normalized.split(separator: "/").last.map(String.init) ?? path
    }

    public var parentPath: String {
        let components = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
        guard components.count > 1 else { return "" }
        return components.dropLast().joined(separator: "/")
    }
}

public struct ExtractionProgress: Sendable {
    public let fraction: Double
    public let currentPath: String
    public let processedBytes: Int64
    public let totalBytes: Int64
}

public struct ExtractionSummary: Sendable {
    public let extractedFiles: Int
    public let skippedEntries: Int
}

public enum ArchiveOverwritePolicy: String, CaseIterable, Sendable {
    case keepBoth
    case overwrite

    public var title: String {
        switch self {
        case .keepBoth: return "保留两者"
        case .overwrite: return "覆盖同名文件"
        }
    }
}

public enum ArchiveError: LocalizedError {
    case cannotCreateReader
    case cannotOpen(String)
    case invalidArchive(String)
    case unsafePath(String)
    case passphraseRequired
    case cancelled
    case fileSystem(String)
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .cannotCreateReader:
            return "无法初始化解压引擎。"
        case .cannotOpen(let detail):
            return "无法打开压缩包：\(detail)"
        case .invalidArchive(let detail):
            return "压缩包格式无效或已损坏：\(detail)"
        case .unsafePath(let path):
            return "压缩包包含不安全的路径：\(path)"
        case .passphraseRequired:
            return "该压缩包已加密，请输入正确密码后重试。"
        case .cancelled:
            return "操作已取消。"
        case .fileSystem(let detail):
            return "写入文件时出错：\(detail)"
        case .unsupportedFormat(let detail):
            return "不支持该压缩格式：\(detail)"
        }
    }
}

public final class CancellationToken: @unchecked Sendable {
    public init() {}

    private let lock = NSLock()
    private var cancelled = false

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
