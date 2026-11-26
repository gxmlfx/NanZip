import CArchive
import Foundation

public enum CompressionFormat: String, CaseIterable, Sendable {
    case zip
    case sevenZip
    case tarGz
    case tarBz2
    case tarXz

    public var title: String {
        switch self {
        case .zip: return "ZIP"
        case .sevenZip: return "7Z"
        case .tarGz: return "TAR.GZ"
        case .tarBz2: return "TAR.BZ2"
        case .tarXz: return "TAR.XZ"
        }
    }

    public var fileExtension: String {
        switch self {
        case .zip: return "zip"
        case .sevenZip: return "7z"
        case .tarGz: return "tar.gz"
        case .tarBz2: return "tar.bz2"
        case .tarXz: return "tar.xz"
        }
    }

    public var supportsEncryption: Bool {
        self == .zip
    }
}

public enum CompressionLevel: Int, CaseIterable, Sendable {
    case fast = 1
    case balanced = 6
    case maximum = 9

    public var title: String {
        switch self {
        case .fast: return "快速"
        case .balanced: return "平衡"
        case .maximum: return "最小体积"
        }
    }
}

public struct CompressionOptions: Sendable {
    public let format: CompressionFormat
    public let level: CompressionLevel
    public let password: String?

    public init(format: CompressionFormat, level: CompressionLevel, password: String? = nil) {
        self.format = format
        self.level = level
        self.password = password?.isEmpty == false ? password : nil
    }
}

public struct CompressionProgress: Sendable {
    public let fraction: Double
    public let currentPath: String
    public let processedBytes: Int64
    public let totalBytes: Int64

    public init(fraction: Double, currentPath: String, processedBytes: Int64, totalBytes: Int64) {
        self.fraction = fraction
        self.currentPath = currentPath
        self.processedBytes = processedBytes
        self.totalBytes = totalBytes
    }
}

public struct CompressionSummary: Sendable {
    public let addedEntries: Int
    public let inputBytes: Int64
    public let outputURL: URL

    public init(addedEntries: Int, inputBytes: Int64, outputURL: URL) {
        self.addedEntries = addedEntries
        self.inputBytes = inputBytes
        self.outputURL = outputURL
    }
}

public enum CompressionService {
    public static func createArchive(
        inputURLs: [URL],
        destinationURL: URL,
        options: CompressionOptions,
        cancellationToken: CancellationToken,
        progress: @escaping @Sendable (CompressionProgress) -> Void
    ) throws -> CompressionSummary {
        if cancellationToken.isCancelled { throw ArchiveError.cancelled }
        guard !inputURLs.isEmpty else {
            throw ArchiveError.fileSystem("没有选择要压缩的文件。")
        }

        let fileManager = FileManager.default
        let rootURL = try commonParent(for: inputURLs)
        let entries = try scanEntries(inputURLs: inputURLs, rootURL: rootURL)
        let totalBytes = entries.reduce(Int64(0)) { partial, entry in
            partial + (entry.isRegularFile ? entry.size : 0)
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".nanzip-\(UUID().uuidString).partial")

        guard let writer = archive_write_new() else {
            throw ArchiveError.cannotCreateReader
        }
        var writerOpen = false
        var completed = false
        defer {
            if writerOpen { archive_write_close(writer) }
            archive_write_free(writer)
            if !completed { try? fileManager.removeItem(at: temporaryURL) }
        }

        try configure(writer, format: options.format, level: options.level, password: options.password)

        let openResult = temporaryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return ARCHIVE_FAILED }
            return archive_write_open_filename(writer, path)
        }
        guard openResult == ARCHIVE_OK else {
            throw writeError(writer, fallback: .fileSystem("无法创建目标压缩包。"))
        }
        writerOpen = true

        var processedBytes: Int64 = 0
        var addedEntries = 0
        var lastReportedBytes: Int64 = -1

        for entry in entries {
            if cancellationToken.isCancelled { throw ArchiveError.cancelled }

            let archivePath = relativePath(for: entry.url, from: rootURL)
            guard !archivePath.isEmpty else { continue }

            guard let archiveEntry = archive_entry_new() else {
                throw ArchiveError.fileSystem("无法创建归档条目。")
            }
            defer { archive_entry_free(archiveEntry) }

            archivePath.withCString { archive_entry_set_pathname(archiveEntry, $0) }
            if let modifiedAt = entry.modifiedAt {
                archive_entry_set_mtime(archiveEntry, time_t(modifiedAt.timeIntervalSince1970), 0)
            }

            if entry.isDirectory {
                archive_entry_set_filetype(archiveEntry, 0o040000)
                archive_entry_set_perm(archiveEntry, 0o755)
                let result = archive_write_header(writer, archiveEntry)
                if result < ARCHIVE_WARN {
                    throw writeError(writer, fallback: .fileSystem("无法写入目录 \(archivePath)。"))
                }
                archive_write_finish_entry(writer)
                addedEntries += 1
                continue
            }

            if entry.isSymlink {
                archive_entry_set_filetype(archiveEntry, 0o120000)
                archive_entry_set_perm(archiveEntry, 0o755)
                if let target = try? fileManager.destinationOfSymbolicLink(atPath: entry.url.path) {
                    target.withCString { archive_entry_set_symlink(archiveEntry, $0) }
                }
                let result = archive_write_header(writer, archiveEntry)
                if result < ARCHIVE_WARN {
                    throw writeError(writer, fallback: .fileSystem("无法写入符号链接 \(archivePath)。"))
                }
                archive_write_finish_entry(writer)
                addedEntries += 1
                continue
            }

            guard entry.isRegularFile else { continue }
            archive_entry_set_filetype(archiveEntry, 0o100000)
            archive_entry_set_perm(archiveEntry, 0o644)
            archive_entry_set_size(archiveEntry, entry.size)

            let headerResult = archive_write_header(writer, archiveEntry)
            if headerResult < ARCHIVE_WARN {
                throw writeError(writer, fallback: .fileSystem("无法写入文件 \(archivePath)。"))
            }

            guard let handle = FileHandle(forReadingAtPath: entry.url.path) else {
                throw ArchiveError.fileSystem("无法读取 \(entry.url.lastPathComponent)。")
            }
            defer { try? handle.close() }

            while true {
                if cancellationToken.isCancelled { throw ArchiveError.cancelled }
                let data = try handle.read(upToCount: 1 << 20) ?? Data()
                if data.isEmpty { break }

                let written = data.withUnsafeBytes { rawBuffer -> Int in
                    guard let baseAddress = rawBuffer.baseAddress else { return 0 }
                    return archive_write_data(writer, baseAddress, data.count)
                }
                if written < 0 {
                    throw writeError(writer, fallback: .fileSystem("写入 \(archivePath) 失败。"))
                }

                processedBytes += Int64(data.count)
                if processedBytes - lastReportedBytes >= 1_000_000 {
                    lastReportedBytes = processedBytes
                    progress(
                        CompressionProgress(
                            fraction: totalBytes > 0
                                ? min(1, Double(processedBytes) / Double(totalBytes))
                                : 0,
                            currentPath: archivePath,
                            processedBytes: processedBytes,
                            totalBytes: totalBytes
                        )
                    )
                }
            }

            archive_write_finish_entry(writer)
            addedEntries += 1
        }

        guard archive_write_close(writer) == ARCHIVE_OK else {
            writerOpen = false
            throw writeError(writer, fallback: .fileSystem("无法完成压缩包。"))
        }
        writerOpen = false

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        completed = true

        progress(
            CompressionProgress(
                fraction: 1,
                currentPath: "完成",
                processedBytes: max(processedBytes, totalBytes),
                totalBytes: max(processedBytes, totalBytes)
            )
        )

        return CompressionSummary(
            addedEntries: addedEntries,
            inputBytes: totalBytes,
            outputURL: destinationURL
        )
    }

    private struct ScannedEntry {
        let url: URL
        let isDirectory: Bool
        let isRegularFile: Bool
        let isSymlink: Bool
        let size: Int64
        let modifiedAt: Date?
    }

    private static func configure(
        _ writer: OpaquePointer,
        format: CompressionFormat,
        level: CompressionLevel,
        password: String?
    ) throws {
        switch format {
        case .zip:
            guard archive_write_set_format_zip(writer) == ARCHIVE_OK else {
                throw writeError(writer, fallback: .unsupportedFormat("ZIP"))
            }
            var options = "compression-level=\(level.rawValue)"
            if password?.isEmpty == false {
                options += ",encryption=aes256"
                password!.withCString { _ = archive_write_set_passphrase(writer, $0) }
            }
            guard archive_write_set_options(writer, options) == ARCHIVE_OK else {
                throw writeError(writer, fallback: .unsupportedFormat("ZIP AES-256"))
            }
        case .sevenZip:
            guard archive_write_set_format_7zip(writer) == ARCHIVE_OK else {
                throw writeError(writer, fallback: .unsupportedFormat("7Z"))
            }
            guard archive_write_set_options(
                writer,
                "compression=lzma2,compression-level=\(level.rawValue)"
            ) == ARCHIVE_OK else {
                throw writeError(writer, fallback: .unsupportedFormat("7Z"))
            }
        case .tarGz:
            guard archive_write_set_format_pax_restricted(writer) == ARCHIVE_OK else {
                throw writeError(writer, fallback: .unsupportedFormat("TAR"))
            }
            guard archive_write_add_filter_gzip(writer) == ARCHIVE_OK else {
                throw writeError(writer, fallback: .unsupportedFormat("GZIP"))
            }
            _ = archive_write_set_options(writer, "compression-level=\(level.rawValue)")
        case .tarBz2:
            guard archive_write_set_format_pax_restricted(writer) == ARCHIVE_OK else {
                throw writeError(writer, fallback: .unsupportedFormat("TAR"))
            }
            guard archive_write_add_filter_bzip2(writer) == ARCHIVE_OK else {
                throw writeError(writer, fallback: .unsupportedFormat("BZIP2"))
            }
            _ = archive_write_set_options(writer, "compression-level=\(level.rawValue)")
        case .tarXz:
            guard archive_write_set_format_pax_restricted(writer) == ARCHIVE_OK else {
                throw writeError(writer, fallback: .unsupportedFormat("TAR"))
            }
            guard archive_write_add_filter_xz(writer) == ARCHIVE_OK else {
                throw writeError(writer, fallback: .unsupportedFormat("XZ"))
            }
            _ = archive_write_set_options(writer, "compression-level=\(level.rawValue)")
        }
    }

    private static func commonParent(for urls: [URL]) throws -> URL {
        guard let first = urls.first else {
            throw ArchiveError.fileSystem("没有输入文件。")
        }
        var commonComponents = first.deletingLastPathComponent().standardizedFileURL.pathComponents
        for url in urls.dropFirst() {
            let components = url.deletingLastPathComponent().standardizedFileURL.pathComponents
            var prefixCount = 0
            while prefixCount < commonComponents.count,
                  prefixCount < components.count,
                  commonComponents[prefixCount] == components[prefixCount] {
                prefixCount += 1
            }
            commonComponents = Array(commonComponents.prefix(prefixCount))
        }
        guard !commonComponents.isEmpty else {
            throw ArchiveError.fileSystem("所选文件不在同一文件系统根目录下。")
        }
        return URL(fileURLWithPath: NSString.path(withComponents: commonComponents))
    }

    private static func scanEntries(inputURLs: [URL], rootURL: URL) throws -> [ScannedEntry] {
        let fileManager = FileManager.default
        var result: [ScannedEntry] = []

        for inputURL in inputURLs {
            let rootValues = try inputURL.resourceValues(forKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                .fileSizeKey, .contentModificationDateKey
            ])
            appendScannedEntry(
                url: inputURL,
                values: rootValues,
                fileManager: fileManager,
                result: &result
            )

            if rootValues.isDirectory == true {
                guard let enumerator = fileManager.enumerator(
                    at: inputURL,
                    includingPropertiesForKeys: [
                        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                        .fileSizeKey, .contentModificationDateKey
                    ],
                    options: [.skipsPackageDescendants],
                    errorHandler: { url, error in
                        NSLog("NanZip scan error for %@: %@", url.path, error.localizedDescription)
                        return true
                    }
                ) else { continue }

                for case let childURL as URL in enumerator {
                    let values = try childURL.resourceValues(forKeys: [
                        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                        .fileSizeKey, .contentModificationDateKey
                    ])
                    appendScannedEntry(
                        url: childURL,
                        values: values,
                        fileManager: fileManager,
                        result: &result
                    )
                }
            }
        }

        return result.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    private static func appendScannedEntry(
        url: URL,
        values: URLResourceValues,
        fileManager: FileManager,
        result: inout [ScannedEntry]
    ) {
        let isSymlink = values.isSymbolicLink == true
        let isDirectory = values.isDirectory == true && !isSymlink
        let isRegularFile = values.isRegularFile == true && !isSymlink
        result.append(
            ScannedEntry(
                url: url,
                isDirectory: isDirectory,
                isRegularFile: isRegularFile,
                isSymlink: isSymlink,
                size: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate
            )
        )
    }

    private static func relativePath(for url: URL, from rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }
        let relative = String(filePath.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative
    }

    private static func writeError(_ writer: OpaquePointer, fallback: ArchiveError) -> ArchiveError {
        guard let message = archive_error_string(writer) else { return fallback }
        return .fileSystem(String(cString: message))
    }
}
