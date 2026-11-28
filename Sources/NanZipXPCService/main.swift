import Foundation
import NanZipCore

final class OperationRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String: CancellationToken] = [:]

    func create(_ id: String) -> CancellationToken {
        let token = CancellationToken()
        lock.lock()
        tokens[id] = token
        lock.unlock()
        return token
    }

    func cancel(_ id: String) {
        lock.lock()
        let token = tokens[id]
        lock.unlock()
        token?.cancel()
    }

    func remove(_ id: String) {
        lock.lock()
        tokens.removeValue(forKey: id)
        lock.unlock()
    }
}

final class ArchiveXPCService: NSObject, NanZipXPCProtocol {
    private let registry = OperationRegistry()

    func perform(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        do {
            let request = try JSONDecoder().decode(ArchiveXPCRequest.self, from: requestData)
            let token = registry.create(request.operationID)
            defer { registry.remove(request.operationID) }
            let response = try execute(request, token: token)
            reply(try JSONEncoder().encode(response))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if let data = try? JSONEncoder().encode(ArchiveXPCFailure(message: message)) {
                reply(data)
            } else {
                reply(Data())
            }
        }
    }

    func cancel(_ operationID: String) {
        registry.cancel(operationID)
    }

    private func execute(
        _ request: ArchiveXPCRequest,
        token: CancellationToken
    ) throws -> ArchiveXPCResponse {
        switch request.operation {
        case .ping:
            return ArchiveXPCResponse()

        case .list:
            let items = try ArchiveService.listArchive(
                at: try archiveURL(request),
                password: request.password,
                filenameEncoding: request.filenameEncoding
            )
            return ArchiveXPCResponse(items: items)

        case .extract:
            let summary = try ArchiveService.extract(
                archiveURL: try archiveURL(request),
                destinationURL: try destinationURL(request),
                selectedPaths: request.selectedPaths,
                totalBytes: 0,
                password: request.password,
                overwritePolicy: request.overwritePolicy,
                filenameEncoding: request.filenameEncoding,
                cancellationToken: token,
                progress: { _ in }
            )
            return ArchiveXPCResponse(
                extractedFiles: summary.extractedFiles,
                skippedEntries: summary.skippedEntries
            )

        case .compress:
            guard let options = request.compressionOptions else {
                throw ArchiveError.fileSystem("压缩参数缺失。")
            }
            let summary = try CompressionService.createArchive(
                inputURLs: request.inputPaths.map(URL.init(fileURLWithPath:)),
                destinationURL: try destinationURL(request),
                options: options,
                cancellationToken: token,
                progress: { _ in }
            )
            return ArchiveXPCResponse(
                outputPath: summary.outputURL.path,
                addedEntries: summary.addedEntries,
                inputBytes: summary.inputBytes
            )

        case .test:
            try ArchiveService.testArchive(at: try archiveURL(request), password: request.password)
            return ArchiveXPCResponse()

        case .add:
            let summary = try ArchiveEditingService.addFiles(
                to: try archiveURL(request),
                fileURLs: request.inputPaths.map(URL.init(fileURLWithPath:)),
                password: request.password,
                cancellationToken: token
            )
            return ArchiveXPCResponse(changedEntries: summary.changedEntries)

        case .replace:
            let summary = try ArchiveEditingService.replaceEntries(
                in: try archiveURL(request),
                replacements: request.replacements.map {
                    ArchiveReplacement(
                        archivePath: $0.archivePath,
                        sourceURL: URL(fileURLWithPath: $0.sourcePath)
                    )
                },
                password: request.password,
                cancellationToken: token
            )
            return ArchiveXPCResponse(changedEntries: summary.changedEntries)

        case .delete:
            let summary = try ArchiveEditingService.deleteEntries(
                from: try archiveURL(request),
                paths: request.selectedPaths ?? [],
                password: request.password,
                cancellationToken: token
            )
            return ArchiveXPCResponse(changedEntries: summary.changedEntries)

        case .preview:
            let result = try ArchivePreviewService.extractEntry(
                archiveURL: try archiveURL(request),
                entryPath: request.entryPath ?? "",
                password: request.password,
                filenameEncoding: request.filenameEncoding,
                workingDirectory: request.destinationPath.map(URL.init(fileURLWithPath:)),
                cancellationToken: token
            )
            return ArchiveXPCResponse(
                outputPath: result.extractedURL.path,
                previewWorkingDirectory: result.workingDirectoryURL.path
            )

        case .repair:
            let summary = try ArchiveRepairService.repairZIP(
                archiveURL: try archiveURL(request),
                destinationURL: try destinationURL(request),
                filenameEncoding: request.compressionOptions?.filenameEncoding ?? .automatic,
                password: request.password,
                cancellationToken: token,
                progress: { _, _ in }
            )
            return ArchiveXPCResponse(
                outputPath: summary.outputURL.path,
                skippedEntries: summary.skippedEntries,
                recoveredFiles: summary.recoveredFiles
            )
        }
    }

    private func archiveURL(_ request: ArchiveXPCRequest) throws -> URL {
        guard let path = request.archivePath else {
            throw ArchiveError.fileSystem("归档路径缺失。")
        }
        return URL(fileURLWithPath: path)
    }

    private func destinationURL(_ request: ArchiveXPCRequest) throws -> URL {
        guard let path = request.destinationPath else {
            throw ArchiveError.fileSystem("目标路径缺失。")
        }
        return URL(fileURLWithPath: path)
    }
}

final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let service = ArchiveXPCService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: NanZipXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
