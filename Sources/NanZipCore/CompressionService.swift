import Foundation

public enum CompressionFormat: String, CaseIterable, Sendable {
    case zip
    case sevenZip
    case tar
    case tarGz
    case tarBz2
    case tarXz

    public var title: String {
        switch self {
        case .zip: return "ZIP"
        case .sevenZip: return "7Z"
        case .tar: return "TAR"
        case .tarGz: return "TAR.GZ"
        case .tarBz2: return "TAR.BZ2"
        case .tarXz: return "TAR.XZ"
        }
    }

    public var fileExtension: String {
        switch self {
        case .zip: return "zip"
        case .sevenZip: return "7z"
        case .tar: return "tar"
        case .tarGz: return "tar.gz"
        case .tarBz2: return "tar.bz2"
        case .tarXz: return "tar.xz"
        }
    }

    public var supportsEncryption: Bool {
        self == .zip || self == .sevenZip
    }

    var sevenZipType: String {
        switch self {
        case .zip: return "zip"
        case .sevenZip: return "7z"
        case .tar, .tarGz, .tarBz2, .tarXz: return "tar"
        }
    }

    var compressionFilterType: String? {
        switch self {
        case .tarGz: return "gzip"
        case .tarBz2: return "bzip2"
        case .tarXz: return "xz"
        default: return nil
        }
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
        let relativeInputs = inputURLs.map { relativePath(for: $0, from: rootURL) }
        let totalBytes = inputURLs.reduce(Int64(0)) { $0 + sizeOfItem($1) }
        let parent = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("nanzip-compress-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workDirectory) }

        let temporaryName = ".nanzip-\(UUID().uuidString).\(options.format.fileExtension)"
        let temporaryOutput = workDirectory.appendingPathComponent(temporaryName)
        let stageBase = workDirectory.appendingPathComponent(
            "archive.\(options.format.fileExtension == "tar.gz" ? "tar" : options.format.fileExtension)"
        )

        var entriesAdded = 0
        if options.format.compressionFilterType == nil {
            try add(
                inputs: relativeInputs,
                to: temporaryOutput,
                format: options.format,
                level: options.level,
                password: options.password,
                workingDirectory: rootURL,
                cancellationToken: cancellationToken
            ) { fraction, path in
                progress(
                    CompressionProgress(
                        fraction: fraction,
                        currentPath: path,
                        processedBytes: Int64(Double(totalBytes) * fraction),
                        totalBytes: totalBytes
                    )
                )
            }
        } else {
            try add(
                inputs: relativeInputs,
                to: stageBase,
                format: .tar,
                level: options.level,
                password: nil,
                workingDirectory: rootURL,
                cancellationToken: cancellationToken
            ) { fraction, path in
                progress(
                    CompressionProgress(
                        fraction: fraction * 0.65,
                        currentPath: path,
                        processedBytes: Int64(Double(totalBytes) * fraction * 0.65),
                        totalBytes: totalBytes
                    )
                )
            }

            let filterType = options.format.compressionFilterType!
            _ = try SevenZipEngine.run(
                arguments: [
                    "a", "-y", "-sccUTF-8", "-bsp1", "-bso1", "-bse1", "-bb1",
                    "-t\(filterType)", "-mx=\(options.level.rawValue)",
                    temporaryOutput.path,
                    stageBase.lastPathComponent
                ],
                workingDirectory: workDirectory,
                cancellationToken: cancellationToken
            ) { fraction, path in
                progress(
                    CompressionProgress(
                        fraction: 0.65 + fraction * 0.35,
                        currentPath: path.isEmpty ? stageBase.lastPathComponent : path,
                        processedBytes: Int64(Double(totalBytes) * (0.65 + fraction * 0.35)),
                        totalBytes: totalBytes
                    )
                )
            }
        }

        entriesAdded = countEntries(inputURLs, relativeInputs: relativeInputs)
        var testArguments = ["t", "-y", "-sccUTF-8", "-bb1"]
        testArguments.append(contentsOf: passwordArguments(options.password))
        testArguments.append(temporaryOutput.path)
        _ = try SevenZipEngine.run(arguments: testArguments)

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryOutput)
        } else {
            try fileManager.moveItem(at: temporaryOutput, to: destinationURL)
        }

        progress(
            CompressionProgress(
                fraction: 1,
                currentPath: "完成",
                processedBytes: totalBytes,
                totalBytes: totalBytes
            )
        )

        return CompressionSummary(
            addedEntries: entriesAdded,
            inputBytes: totalBytes,
            outputURL: destinationURL
        )
    }

    public static func passwordArguments(_ password: String?) -> [String] {
        guard let password, !password.isEmpty else { return [] }
        return ["-p\(password)"]
    }

    private static func add(
        inputs: [String],
        to archiveURL: URL,
        format: CompressionFormat,
        level: CompressionLevel,
        password: String?,
        workingDirectory: URL,
        cancellationToken: CancellationToken,
        progress: @escaping @Sendable (Double, String) -> Void
    ) throws {
        var arguments: [String] = [
            "a", "-y", "-sccUTF-8", "-bsp1", "-bso1", "-bse1", "-bb1",
            "-t\(format.sevenZipType)", "-mx=\(level.rawValue)", "-mmt=on"
        ]
        if format == .zip, password?.isEmpty == false {
            arguments.append("-mem=AES256")
        }
        arguments.append(contentsOf: passwordArguments(format.supportsEncryption ? password : nil))
        arguments.append(archiveURL.path)
        arguments.append(contentsOf: inputs)
        _ = try SevenZipEngine.run(
            arguments: arguments,
            workingDirectory: workingDirectory,
            cancellationToken: cancellationToken,
            progress: progress
        )
    }

    private static func countEntries(_ inputURLs: [URL], relativeInputs: [String]) -> Int {
        let fileManager = FileManager.default
        var count = 0
        for url in inputURLs {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: nil
                ) else { continue }
                while enumerator.nextObject() != nil { count += 1 }
            } else {
                count += 1
            }
        }
        return max(count, relativeInputs.count)
    }

    private static func commonParent(for urls: [URL]) throws -> URL {
        guard let first = urls.first else {
            throw ArchiveError.fileSystem("没有输入文件。")
        }
        var commonComponents = first.standardizedFileURL
            .deletingLastPathComponent().pathComponents
        for url in urls.dropFirst() {
            let components = url.standardizedFileURL.deletingLastPathComponent().pathComponents
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

    private static func relativePath(for url: URL, from rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func sizeOfItem(_ url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values?.fileSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}
