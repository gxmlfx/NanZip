import Foundation

public enum ArchiveService {
    public static let supportedExtensions: Set<String> = [
        "zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2",
        "xz", "txz", "zst", "tzst", "cab", "iso", "cpio", "lz", "lzma", "z"
    ]

    public static func listArchive(at url: URL, password: String?) throws -> [ArchiveItem] {
        if isTarCompressed(url) {
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("nanzip-list-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
            let innerTar = try extractOuterArchive(url, to: temporaryDirectory)
            return try listDirect(at: innerTar, password: password)
        }
        return try listDirect(at: url, password: password)
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

        let items = try listArchive(at: archiveURL, password: password)
        let pathsToValidate: [String]
        if let selectedPaths {
            pathsToValidate = items.map(\.path).filter { selectedPaths.contains($0) }
        } else {
            pathsToValidate = items.map(\.path)
        }
        for path in pathsToValidate {
            _ = try validatedRelativePath(path)
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        if isTarCompressed(archiveURL) {
            let temporaryDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("nanzip-extract-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: temporaryDirectory) }

            let innerTar = try extractOuterArchive(archiveURL, to: temporaryDirectory)
            try runExtraction(
                archiveURL: innerTar,
                destinationURL: destinationURL,
                selectedPaths: selectedPaths,
                password: password,
                overwritePolicy: overwritePolicy,
                cancellationToken: cancellationToken,
                progress: progress
            )
        } else {
            try runExtraction(
                archiveURL: archiveURL,
                destinationURL: destinationURL,
                selectedPaths: selectedPaths,
                password: password,
                overwritePolicy: overwritePolicy,
                cancellationToken: cancellationToken,
                progress: progress
            )
        }

        let selectedItems: [ArchiveItem]
        if let selectedPaths {
            selectedItems = items.filter { selectedPaths.contains($0.path) && !$0.isDirectory }
        } else {
            selectedItems = items.filter { !$0.isDirectory }
        }

        progress(
            ExtractionProgress(
                fraction: 1,
                currentPath: "完成",
                processedBytes: totalBytes,
                totalBytes: totalBytes
            )
        )
        return ExtractionSummary(extractedFiles: selectedItems.count, skippedEntries: 0)
    }

    public static func testArchive(at url: URL, password: String?) throws {
        var arguments = ["t", "-y", "-sccUTF-8", "-bb1"]
        arguments.append(contentsOf: CompressionService.passwordArguments(password))
        arguments.append(url.path)
        _ = try SevenZipEngine.run(arguments: arguments)
    }

    private static func listDirect(at url: URL, password: String?) throws -> [ArchiveItem] {
        var arguments = ["l", "-slt", "-ba", "-y", "-sccUTF-8"]
        arguments.append(contentsOf: CompressionService.passwordArguments(password))
        arguments.append(url.path)
        let result = try SevenZipEngine.run(arguments: arguments)
        return parseListOutput(result.standardOutput)
            .filter { !$0.path.isEmpty && $0.path != "." }
            .sorted(by: archivePathSort)
    }

    private static func runExtraction(
        archiveURL: URL,
        destinationURL: URL,
        selectedPaths: Set<String>?,
        password: String?,
        overwritePolicy: ArchiveOverwritePolicy,
        cancellationToken: CancellationToken,
        progress: @escaping @Sendable (ExtractionProgress) -> Void
    ) throws {
        var arguments: [String] = [
            "x", "-y", "-sccUTF-8", "-bsp1", "-bso1", "-bse1", "-bb1", "-spd",
            "-o\(destinationURL.path)",
            overwritePolicy == .overwrite ? "-aoa" : "-aou"
        ]
        arguments.append(contentsOf: CompressionService.passwordArguments(password))
        if let selectedPaths {
            for path in selectedPaths.sorted() {
                arguments.append("-i!\(path)")
            }
        }
        arguments.append(archiveURL.path)

        _ = try SevenZipEngine.run(
            arguments: arguments,
            cancellationToken: cancellationToken
        ) { fraction, path in
            progress(
                ExtractionProgress(
                    fraction: fraction,
                    currentPath: path,
                    processedBytes: 0,
                    totalBytes: 0
                )
            )
        }
    }

    private static func extractOuterArchive(_ archiveURL: URL, to directory: URL) throws -> URL {
        var arguments = [
            "x", "-y", "-sccUTF-8", "-bd",
            "-o\(directory.path)",
            archiveURL.path
        ]
        if archiveURL.pathExtension.lowercased() == "tgz" {
            arguments.insert("-tgzip", at: 1)
        }
        _ = try SevenZipEngine.run(arguments: arguments)
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ArchiveError.invalidArchive("无法读取外层压缩流")
        }
        for case let candidate as URL in enumerator {
            if candidate.pathExtension.lowercased() == "tar" {
                return candidate
            }
        }
        throw ArchiveError.invalidArchive("压缩流中没有找到 TAR 数据")
    }

    private static func isTarCompressed(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") ||
            name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz") ||
            name.hasSuffix(".tbz2") || name.hasSuffix(".tar.xz") ||
            name.hasSuffix(".txz")
    }

    private static func parseListOutput(_ output: String) -> [ArchiveItem] {
        let normalized = output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var items: [ArchiveItem] = []

        for block in blocks {
            var fields: [String: String] = [:]
            for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
                guard let separator = line.range(of: " = ") else { continue }
                fields[String(line[..<separator.lowerBound])] = String(line[separator.upperBound...])
            }
            guard let path = fields["Path"], !path.isEmpty else { continue }
            let attributes = fields["Attributes"]?.trimmingCharacters(in: .whitespaces) ?? ""
            let size = Int64(fields["Size"] ?? "") ?? 0
            let packedSize = Int64(fields["Packed Size"] ?? "") ?? 0
            items.append(
                ArchiveItem(
                    path: path.replacingOccurrences(of: "\\", with: "/"),
                    size: max(0, size),
                    compressedSize: max(0, packedSize),
                    modifiedAt: parseDate(fields["Modified"]),
                    isDirectory: fields["Folder"] == "+",
                    isSymlink: attributes.first == "l",
                    isEncrypted: fields["Encrypted"] == "+",
                    method: fields["Method"] ?? ""
                )
            )
        }
        return items
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: value)
    }

    private static func archivePathSort(_ lhs: ArchiveItem, _ rhs: ArchiveItem) -> Bool {
        let lhsParts = lhs.path.split(separator: "/").map(String.init)
        let rhsParts = rhs.path.split(separator: "/").map(String.init)
        for (left, right) in zip(lhsParts, rhsParts) where left != right {
            return left.localizedStandardCompare(right) == .orderedAscending
        }
        return lhsParts.count < rhsParts.count
    }

    private static func validatedRelativePath(_ path: String) throws -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/", omittingEmptySubsequences: true)
        guard !normalized.hasPrefix("/"), !components.contains("..") else {
            throw ArchiveError.unsafePath(path)
        }
        return normalized
    }
}
