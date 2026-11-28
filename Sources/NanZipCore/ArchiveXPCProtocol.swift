import Foundation

@objc public protocol NanZipXPCProtocol: NSObjectProtocol {
    func perform(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
    func cancel(_ operationID: String)
}

@objc public protocol NanZipXPCProgressProtocol: NSObjectProtocol {
    func update(_ eventData: Data)
}

public struct ArchiveXPCProgressEvent: Codable, Sendable {
    public let operationID: String
    public let fraction: Double
    public let currentPath: String
    public let processedBytes: Int64
    public let totalBytes: Int64

    public init(
        operationID: String,
        fraction: Double,
        currentPath: String,
        processedBytes: Int64 = 0,
        totalBytes: Int64 = 0
    ) {
        self.operationID = operationID
        self.fraction = min(max(fraction, 0), 1)
        self.currentPath = currentPath
        self.processedBytes = processedBytes
        self.totalBytes = totalBytes
    }
}

public enum ArchiveXPCOperation: String, Codable, Sendable {
    case ping
    case list
    case extract
    case compress
    case test
    case add
    case replace
    case delete
    case preview
    case repair
}

public struct ArchiveXPCReplacement: Codable, Sendable {
    public let archivePath: String
    public let sourcePath: String

    public init(archivePath: String, sourcePath: String) {
        self.archivePath = archivePath
        self.sourcePath = sourcePath
    }
}

public struct ArchiveXPCRequest: Codable, Sendable {
    public let operationID: String
    public let operation: ArchiveXPCOperation
    public let archivePath: String?
    public let destinationPath: String?
    public let inputPaths: [String]
    public let selectedPaths: Set<String>?
    public let entryPath: String?
    public let password: String?
    public let overwritePolicy: ArchiveOverwritePolicy
    public let filenameEncoding: ArchiveFilenameEncoding
    public let compressionOptions: CompressionOptions?
    public let replacements: [ArchiveXPCReplacement]
    public let stagingRootPath: String?

    public init(
        operationID: String = UUID().uuidString,
        operation: ArchiveXPCOperation,
        archivePath: String? = nil,
        destinationPath: String? = nil,
        inputPaths: [String] = [],
        selectedPaths: Set<String>? = nil,
        entryPath: String? = nil,
        password: String? = nil,
        overwritePolicy: ArchiveOverwritePolicy = .keepBoth,
        filenameEncoding: ArchiveFilenameEncoding = .automatic,
        compressionOptions: CompressionOptions? = nil,
        replacements: [ArchiveXPCReplacement] = [],
        stagingRootPath: String? = nil
    ) {
        self.operationID = operationID
        self.operation = operation
        self.archivePath = archivePath
        self.destinationPath = destinationPath
        self.inputPaths = inputPaths
        self.selectedPaths = selectedPaths
        self.entryPath = entryPath
        self.password = password
        self.overwritePolicy = overwritePolicy
        self.filenameEncoding = filenameEncoding
        self.compressionOptions = compressionOptions
        self.replacements = replacements
        self.stagingRootPath = stagingRootPath
    }

    public func replacingStagingRoot(_ path: String) -> ArchiveXPCRequest {
        ArchiveXPCRequest(
            operationID: operationID,
            operation: operation,
            archivePath: archivePath,
            destinationPath: destinationPath,
            inputPaths: inputPaths,
            selectedPaths: selectedPaths,
            entryPath: entryPath,
            password: password,
            overwritePolicy: overwritePolicy,
            filenameEncoding: filenameEncoding,
            compressionOptions: compressionOptions,
            replacements: replacements,
            stagingRootPath: path
        )
    }

    public func replacingArchivePath(_ path: String?) -> ArchiveXPCRequest {
        replacing(archivePath: path)
    }

    public func replacingDestinationPath(_ path: String?) -> ArchiveXPCRequest {
        replacing(destinationPath: path)
    }

    public func replacingInputPaths(_ paths: [String]) -> ArchiveXPCRequest {
        replacing(inputPaths: paths)
    }

    public func replacingReplacements(_ replacements: [ArchiveXPCReplacement]) -> ArchiveXPCRequest {
        replacing(replacements: replacements)
    }

    private func replacing(
        archivePath: String? = nil,
        destinationPath: String? = nil,
        inputPaths: [String]? = nil,
        replacements: [ArchiveXPCReplacement]? = nil
    ) -> ArchiveXPCRequest {
        ArchiveXPCRequest(
            operationID: operationID,
            operation: operation,
            archivePath: archivePath ?? self.archivePath,
            destinationPath: destinationPath ?? self.destinationPath,
            inputPaths: inputPaths ?? self.inputPaths,
            selectedPaths: selectedPaths,
            entryPath: entryPath,
            password: password,
            overwritePolicy: overwritePolicy,
            filenameEncoding: filenameEncoding,
            compressionOptions: compressionOptions,
            replacements: replacements ?? self.replacements,
            stagingRootPath: stagingRootPath
        )
    }
}

public struct ArchiveXPCResponse: Codable, Sendable {
    public var items: [ArchiveItem]?
    public var outputPath: String?
    public var extractedFiles: Int?
    public var skippedEntries: Int?
    public var addedEntries: Int?
    public var inputBytes: Int64?
    public var changedEntries: Int?
    public var recoveredFiles: Int?
    public var previewWorkingDirectory: String?

    public init(
        items: [ArchiveItem]? = nil,
        outputPath: String? = nil,
        extractedFiles: Int? = nil,
        skippedEntries: Int? = nil,
        addedEntries: Int? = nil,
        inputBytes: Int64? = nil,
        changedEntries: Int? = nil,
        recoveredFiles: Int? = nil,
        previewWorkingDirectory: String? = nil
    ) {
        self.items = items
        self.outputPath = outputPath
        self.extractedFiles = extractedFiles
        self.skippedEntries = skippedEntries
        self.addedEntries = addedEntries
        self.inputBytes = inputBytes
        self.changedEntries = changedEntries
        self.recoveredFiles = recoveredFiles
        self.previewWorkingDirectory = previewWorkingDirectory
    }
}

public struct ArchiveXPCFailure: Codable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}
