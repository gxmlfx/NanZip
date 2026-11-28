import Foundation

@objc public protocol NanZipXPCProtocol: NSObjectProtocol {
    func perform(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
    func cancel(_ operationID: String)
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
        replacements: [ArchiveXPCReplacement] = []
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
