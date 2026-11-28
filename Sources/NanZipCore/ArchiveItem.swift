import Foundation

public struct ArchiveItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let path: String
    public let size: Int64
    public let compressedSize: Int64
    public let modifiedAt: Date?
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let isEncrypted: Bool
    public let method: String

    public init(
        id: UUID = UUID(),
        path: String,
        size: Int64,
        compressedSize: Int64 = 0,
        modifiedAt: Date?,
        isDirectory: Bool,
        isSymlink: Bool = false,
        isEncrypted: Bool = false,
        method: String = ""
    ) {
        self.id = id
        self.path = path
        self.size = size
        self.compressedSize = compressedSize
        self.modifiedAt = modifiedAt
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isEncrypted = isEncrypted
        self.method = method
    }

    public var compressionRatio: Double? {
        guard size > 0, compressedSize > 0 else { return nil }
        return Double(compressedSize) / Double(size)
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

    public init(
        fraction: Double,
        currentPath: String,
        processedBytes: Int64,
        totalBytes: Int64
    ) {
        self.fraction = fraction
        self.currentPath = currentPath
        self.processedBytes = processedBytes
        self.totalBytes = totalBytes
    }
}

public struct ExtractionSummary: Sendable {
    public let extractedFiles: Int
    public let skippedEntries: Int

    public init(extractedFiles: Int, skippedEntries: Int) {
        self.extractedFiles = extractedFiles
        self.skippedEntries = skippedEntries
    }
}

public enum ArchiveOverwritePolicy: String, CaseIterable, Codable, Sendable {
    case keepBoth
    case overwrite
    case skip
    case newerOnly
    case ask

    public var title: String {
        switch self {
        case .keepBoth: return "保留两者"
        case .overwrite: return "覆盖同名文件"
        case .skip: return "跳过已存在文件"
        case .newerOnly: return "仅覆盖较旧文件"
        case .ask: return "每次询问"
        }
    }

    public var sevenZipArgument: String {
        switch self {
        case .keepBoth: return "-aou"
        case .overwrite, .ask: return "-aoa"
        case .skip: return "-aos"
        case .newerOnly: return "-aot"
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
