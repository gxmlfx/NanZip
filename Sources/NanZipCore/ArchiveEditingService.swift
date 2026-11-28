import Foundation

public struct ArchiveReplacement: Sendable {
    public let archivePath: String
    public let sourceURL: URL

    public init(archivePath: String, sourceURL: URL) {
        self.archivePath = archivePath
        self.sourceURL = sourceURL
    }
}

public struct ArchiveEditSummary: Sendable {
    public let changedEntries: Int
    public let archiveURL: URL

    public init(changedEntries: Int, archiveURL: URL) {
        self.changedEntries = changedEntries
        self.archiveURL = archiveURL
    }
}

public enum ArchiveEditingService {
    public static func addFiles(
        to archiveURL: URL,
        fileURLs: [URL],
        password: String?,
        cancellationToken: CancellationToken
    ) throws -> ArchiveEditSummary {
        guard !fileURLs.isEmpty else {
            throw ArchiveError.fileSystem("没有选择要添加的文件。")
        }
        let replacements = fileURLs.map {
            ArchiveReplacement(archivePath: $0.lastPathComponent, sourceURL: $0)
        }
        return try update(
            archiveURL: archiveURL,
            replacements: replacements,
            password: password,
            cancellationToken: cancellationToken,
            operationName: "添加"
        )
    }

    public static func replaceEntries(
        in archiveURL: URL,
        replacements: [ArchiveReplacement],
        password: String?,
        cancellationToken: CancellationToken
    ) throws -> ArchiveEditSummary {
        guard !replacements.isEmpty else {
            throw ArchiveError.fileSystem("没有选择要替换的归档内容。")
        }
        return try update(
            archiveURL: archiveURL,
            replacements: replacements,
            password: password,
            cancellationToken: cancellationToken,
            operationName: "替换"
        )
    }

    public static func deleteEntries(
        from archiveURL: URL,
        paths: Set<String>,
        password: String?,
        cancellationToken: CancellationToken
    ) throws -> ArchiveEditSummary {
        guard !paths.isEmpty else {
            throw ArchiveError.fileSystem("没有选择要删除的归档内容。")
        }

        let workDirectory = try makeWorkDirectory(for: archiveURL)
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        let workingArchive = workDirectory.appendingPathComponent(archiveURL.lastPathComponent)
        try FileManager.default.copyItem(at: archiveURL, to: workingArchive)

        for path in paths {
            _ = try validatedRelativePath(path)
        }

        var arguments = ["d", "-y", "-sccUTF-8", "-bb1"]
        arguments.append(contentsOf: CompressionService.passwordArguments(password))
        arguments.append(workingArchive.path)
        arguments.append(contentsOf: paths.sorted())
        _ = try SevenZipEngine.run(
            arguments: arguments,
            cancellationToken: cancellationToken
        )

        try ArchiveService.testArchive(at: workingArchive, password: password)
        try replaceOriginal(archiveURL, with: workingArchive)
        return ArchiveEditSummary(changedEntries: paths.count, archiveURL: archiveURL)
    }

    private static func update(
        archiveURL: URL,
        replacements: [ArchiveReplacement],
        password: String?,
        cancellationToken: CancellationToken,
        operationName: String
    ) throws -> ArchiveEditSummary {
        let fileManager = FileManager.default
        let workDirectory = try makeWorkDirectory(for: archiveURL)
        defer { try? fileManager.removeItem(at: workDirectory) }

        let workingArchive = workDirectory.appendingPathComponent(archiveURL.lastPathComponent)
        let stagingRoot = workDirectory.appendingPathComponent("staging", isDirectory: true)
        try fileManager.copyItem(at: archiveURL, to: workingArchive)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        var relativePaths: [String] = []
        for replacement in replacements {
            let relative = try validatedRelativePath(replacement.archivePath)
            let stageURL = stagingRoot.appendingPathComponent(relative)
            try fileManager.createDirectory(
                at: stageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: stageURL.path) {
                try fileManager.removeItem(at: stageURL)
            }
            try fileManager.copyItem(at: replacement.sourceURL, to: stageURL)
            relativePaths.append(relative)
        }

        var arguments = ["u", "-y", "-sccUTF-8", "-bb1", "-spd", "-mmt=on"]
        arguments.append(contentsOf: CompressionService.passwordArguments(password))
        arguments.append(workingArchive.path)
        arguments.append(contentsOf: relativePaths)
        _ = try SevenZipEngine.run(
            arguments: arguments,
            workingDirectory: stagingRoot,
            cancellationToken: cancellationToken
        )

        try ArchiveService.testArchive(at: workingArchive, password: password)
        try replaceOriginal(archiveURL, with: workingArchive)
        return ArchiveEditSummary(
            changedEntries: replacements.count,
            archiveURL: archiveURL
        )
    }

    private static func makeWorkDirectory(for archiveURL: URL) throws -> URL {
        let directory = archiveURL.deletingLastPathComponent()
        let work = directory.appendingPathComponent(
            ".nanzip-edit-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        return work
    }

    private static func replaceOriginal(_ original: URL, with updated: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: original.path) {
            _ = try fileManager.replaceItemAt(original, withItemAt: updated)
        } else {
            try fileManager.moveItem(at: updated, to: original)
        }
    }

    private static func validatedRelativePath(_ path: String) throws -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/", omittingEmptySubsequences: true)
        guard !normalized.hasPrefix("/"), !components.contains(".."), !components.isEmpty else {
            throw ArchiveError.unsafePath(path)
        }
        return components.joined(separator: "/")
    }
}
