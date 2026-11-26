import CArchive
import Foundation

public enum ArchiveService {
    public static let supportedExtensions: Set<String> = [
        "zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2",
        "xz", "txz", "zst", "tzst", "cab", "iso", "cpio", "lz", "lzma", "z"
    ]

    public static func listArchive(at url: URL, password: String?) throws -> [ArchiveItem] {
        let reader = try openReader(at: url, password: password)
        defer { archive_read_free(reader) }

        var items: [ArchiveItem] = []
        var entry: OpaquePointer?

        while true {
            let result = archive_read_next_header(reader, &entry)
            if result == ARCHIVE_EOF { break }
            if result != ARCHIVE_OK {
                throw mappedError(reader, fallback: .invalidArchive(errorMessage(reader)))
            }

            guard let entry else { continue }
            guard let rawPath = archive_entry_pathname(entry) else {
                archive_read_data_skip(reader)
                continue
            }

            let path = normalizedArchivePath(String(cString: rawPath))
            guard !path.isEmpty else {
                archive_read_data_skip(reader)
                continue
            }

            let fileType = archive_entry_filetype(entry)
            let isDirectory = fileType == 0o040000
            let isSymlink = fileType == 0o120000
            let size: Int64
            if archive_entry_size_is_set(entry) != 0 {
                size = max(0, archive_entry_size(entry))
            } else {
                size = 0
            }

            let modifiedAt: Date?
            if archive_entry_mtime_is_set(entry) != 0 {
                modifiedAt = Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry)))
            } else {
                modifiedAt = nil
            }

            items.append(
                ArchiveItem(
                    path: path,
                    size: size,
                    modifiedAt: modifiedAt,
                    isDirectory: isDirectory,
                    isSymlink: isSymlink
                )
            )

            archive_read_data_skip(reader)
        }

        return items.sorted { lhs, rhs in
            let lhsParts = lhs.path.split(separator: "/").map(String.init)
            let rhsParts = rhs.path.split(separator: "/").map(String.init)
            for (left, right) in zip(lhsParts, rhsParts) where left != right {
                return left.localizedStandardCompare(right) == .orderedAscending
            }
            return lhsParts.count < rhsParts.count
        }
    }

    public static func extract(
        archiveURL: URL,
        destinationURL: URL,
        selectedPaths: Set<String>?,
        totalBytes: Int64,
        password: String?,
        overwritePolicy: ArchiveOverwritePolicy,
        cancellationToken: CancellationToken,
        progress: @escaping @Sendable (ExtractionProgress) -> Void
    ) throws -> ExtractionSummary {
        if cancellationToken.isCancelled { throw ArchiveError.cancelled }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )

        let reader = try openReader(at: archiveURL, password: password)
        defer { archive_read_free(reader) }

        var entry: OpaquePointer?
        var extractedFiles = 0
        var skippedEntries = 0
        var processedBytes: Int64 = 0
        var lastReportedBytes: Int64 = -1

        while true {
            if cancellationToken.isCancelled { throw ArchiveError.cancelled }

            let result = archive_read_next_header(reader, &entry)
            if result == ARCHIVE_EOF { break }
            if result != ARCHIVE_OK {
                throw mappedError(reader, fallback: .invalidArchive(errorMessage(reader)))
            }

            guard let entry else { continue }
            guard let rawPath = archive_entry_pathname(entry) else {
                skippedEntries += 1
                archive_read_data_skip(reader)
                continue
            }

            let archivePath = normalizedArchivePath(String(cString: rawPath))
            guard !archivePath.isEmpty else {
                skippedEntries += 1
                archive_read_data_skip(reader)
                continue
            }

            if let selectedPaths, !selectedPaths.contains(archivePath) {
                archive_read_data_skip(reader)
                continue
            }

            let fileType = archive_entry_filetype(entry)
            let isDirectory = fileType == 0o040000
            let isRegularFile = fileType == 0o100000 || fileType == 0
            let isSymlink = fileType == 0o120000

            if isSymlink {
                skippedEntries += 1
                archive_read_data_skip(reader)
                continue
            }

            guard isDirectory || isRegularFile else {
                skippedEntries += 1
                archive_read_data_skip(reader)
                continue
            }

            let destination = try safeDestination(for: archivePath, root: destinationURL)

            if isDirectory {
                do {
                    try fileManager.createDirectory(
                        at: destination,
                        withIntermediateDirectories: true
                    )
                    applyMetadata(from: entry, to: destination)
                } catch {
                    throw ArchiveError.fileSystem(error.localizedDescription)
                }
                archive_read_data_skip(reader)
                continue
            }

            do {
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                throw ArchiveError.fileSystem(error.localizedDescription)
            }

            let finalURL = resolvedFileURL(
                destination,
                overwritePolicy: overwritePolicy,
                fileManager: fileManager
            )

            let temporaryURL = finalURL
                .deletingLastPathComponent()
                .appendingPathComponent(".arcbox-\(UUID().uuidString).partial")

            fileManager.createFile(atPath: temporaryURL.path, contents: nil)
            guard let handle = FileHandle(forWritingAtPath: temporaryURL.path) else {
                throw ArchiveError.fileSystem("无法创建临时文件 \(temporaryURL.lastPathComponent)")
            }

            var completed = false
            defer {
                try? handle.close()
                if !completed {
                    try? fileManager.removeItem(at: temporaryURL)
                }
            }

            var buffer = [UInt8](repeating: 0, count: 1 << 20)
            while true {
                if cancellationToken.isCancelled { throw ArchiveError.cancelled }

                let byteCount = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                    guard let baseAddress = rawBuffer.baseAddress else { return 0 }
                    return archive_read_data(reader, baseAddress, rawBuffer.count)
                }

                if byteCount == 0 { break }
                if byteCount < 0 {
                    throw mappedError(reader, fallback: .invalidArchive(errorMessage(reader)))
                }

                do {
                    try handle.write(contentsOf: Data(buffer[0..<byteCount]))
                } catch {
                    throw ArchiveError.fileSystem(error.localizedDescription)
                }

                processedBytes += Int64(byteCount)
                if processedBytes - lastReportedBytes >= 1_000_000 {
                    lastReportedBytes = processedBytes
                    let fraction = totalBytes > 0
                        ? min(1, Double(processedBytes) / Double(totalBytes))
                        : 0
                    progress(
                        ExtractionProgress(
                            fraction: fraction,
                            currentPath: archivePath,
                            processedBytes: processedBytes,
                            totalBytes: totalBytes
                        )
                    )
                }
            }

            try handle.close()
            completed = true

            do {
                if fileManager.fileExists(atPath: finalURL.path) {
                    try fileManager.removeItem(at: finalURL)
                }
                try fileManager.moveItem(at: temporaryURL, to: finalURL)
                applyMetadata(from: entry, to: finalURL)
            } catch {
                throw ArchiveError.fileSystem(error.localizedDescription)
            }

            extractedFiles += 1
        }

        progress(
            ExtractionProgress(
                fraction: 1,
                currentPath: "完成",
                processedBytes: max(processedBytes, totalBytes),
                totalBytes: max(processedBytes, totalBytes)
            )
        )

        return ExtractionSummary(
            extractedFiles: extractedFiles,
            skippedEntries: skippedEntries
        )
    }

    private static func openReader(at url: URL, password: String?) throws -> OpaquePointer {
        guard let reader = archive_read_new() else {
            throw ArchiveError.cannotCreateReader
        }

        archive_read_support_filter_all(reader)
        archive_read_support_format_all(reader)

        if let password, !password.isEmpty {
            archive_read_add_passphrase(reader, password)
        }

        let openResult = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return ARCHIVE_FAILED }
            return archive_read_open_filename(reader, path, 1 << 20)
        }

        guard openResult == ARCHIVE_OK else {
            let error = mappedError(reader, fallback: .cannotOpen(errorMessage(reader)))
            archive_read_free(reader)
            throw error
        }

        return reader
    }

    private static func safeDestination(for path: String, root: URL) throws -> URL {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/") else {
            throw ArchiveError.unsafePath(path)
        }

        let components = normalized.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains("..") else {
            throw ArchiveError.unsafePath(path)
        }

        let destination = components.reduce(root.standardizedFileURL) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: false)
        }
        let rootPath = root.standardizedFileURL.path
        let destinationPath = destination.standardizedFileURL.path

        guard destinationPath == rootPath || destinationPath.hasPrefix(rootPath + "/") else {
            throw ArchiveError.unsafePath(path)
        }
        return destination
    }

    private static func resolvedFileURL(
        _ url: URL,
        overwritePolicy: ArchiveOverwritePolicy,
        fileManager: FileManager
    ) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }
        if overwritePolicy == .overwrite { return url }

        let directory = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var counter = 2

        while true {
            let candidateName = ext.isEmpty
                ? "\(stem) (\(counter))"
                : "\(stem) (\(counter)).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    private static func applyMetadata(from entry: OpaquePointer, to url: URL) {
        var attributes: [FileAttributeKey: Any] = [:]

        if archive_entry_mtime_is_set(entry) != 0 {
            attributes[.modificationDate] = Date(
                timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry))
            )
        }

        let permissions = archive_entry_perm(entry)
        if permissions != 0 {
            attributes[.posixPermissions] = NSNumber(value: permissions)
        }

        if !attributes.isEmpty {
            try? FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
        }
    }

    private static func normalizedArchivePath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func errorMessage(_ reader: OpaquePointer) -> String {
        guard let message = archive_error_string(reader) else {
            return "未知错误"
        }
        return String(cString: message)
    }

    private static func mappedError(
        _ reader: OpaquePointer,
        fallback: ArchiveError
    ) -> ArchiveError {
        let message = errorMessage(reader)
        let lowercased = message.lowercased()
        if lowercased.contains("passphrase") || lowercased.contains("password") {
            return .passphraseRequired
        }
        if lowercased.contains("truncated") || lowercased.contains("corrupt") {
            return .invalidArchive(message)
        }
        return fallback
    }
}
