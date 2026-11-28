import Foundation

public struct ArchivePreviewResult: Sendable {
    public let extractedURL: URL
    public let workingDirectoryURL: URL

    public init(extractedURL: URL, workingDirectoryURL: URL) {
        self.extractedURL = extractedURL
        self.workingDirectoryURL = workingDirectoryURL
    }
}

public enum ArchivePreviewService {
    public static func extractEntry(
        archiveURL: URL,
        entryPath: String,
        password: String?,
        filenameEncoding: ArchiveFilenameEncoding = .automatic,
        workingDirectory: URL? = nil,
        cancellationToken: CancellationToken = CancellationToken()
    ) throws -> ArchivePreviewResult {
        let normalized = try validatedRelativePath(entryPath)
        let rawPath = try ArchiveService.nameMappings(
            at: archiveURL,
            password: password,
            filenameEncoding: filenameEncoding
        ).first(where: { $0.displayPath == normalized })?.rawPath ?? normalized
        let fileManager = FileManager.default
        let work = workingDirectory ?? fileManager.temporaryDirectory
            .appendingPathComponent("nanzip-preview-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)

        var arguments = [
            "x", "-y", "-sccUTF-8", "-bso1", "-bse1", "-bb1", "-spd",
            "-o\(work.path)"
        ]
        arguments.append(contentsOf: CompressionService.passwordArguments(password))
        arguments.append("-i!\(rawPath)")
        arguments.append(archiveURL.path)
        _ = try SevenZipEngine.run(
            arguments: arguments,
            cancellationToken: cancellationToken
        )

        let output = work.appendingPathComponent(rawPath)
        guard fileManager.fileExists(atPath: output.path) else {
            throw ArchiveError.fileSystem("无法从归档中提取预览文件。")
        }
        return ArchivePreviewResult(extractedURL: output, workingDirectoryURL: work)
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
