import Darwin
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

    func perform(
        _ requestData: Data,
        withReply reply: @escaping (Data) -> Void
    ) {
        do {
            let request = try JSONDecoder().decode(ArchiveXPCRequest.self, from: requestData)
            try validateAccess(for: request)
            let token = registry.create(request.operationID)
            defer { registry.remove(request.operationID) }
            let progressProxy = NSXPCConnection.current()?.remoteObjectProxy as? NanZipXPCProgressProtocol
            let response = try execute(
                request,
                token: token,
                progress: { fraction, path, processedBytes, totalBytes in
                    let event = ArchiveXPCProgressEvent(
                        operationID: request.operationID,
                        fraction: fraction,
                        currentPath: path,
                        processedBytes: processedBytes,
                        totalBytes: totalBytes
                    )
                    if let data = try? JSONEncoder().encode(event) {
                        progressProxy?.update(data)
                    }
                }
            )
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
        token: CancellationToken,
        progress: @escaping @Sendable (Double, String, Int64, Int64) -> Void
    ) throws -> ArchiveXPCResponse {
        progress(0.02, "XPC 服务正在准备…", 0, 0)
        switch request.operation {
        case .ping:
            progress(1, "XPC 服务可用", 0, 0)
            return ArchiveXPCResponse()

        case .list:
            let staging = try StagingArea()
            let staged = try staging.stageArchive(try archiveURL(request))
            progress(0.08, "已复制归档到 XPC 沙盒…", 0, 0)
            let items = try ArchiveService.listArchive(
                at: staged,
                password: request.password,
                filenameEncoding: request.filenameEncoding
            )
            progress(1, "归档目录读取完成", 0, 0)
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
                progress: { update in
                    progress(
                        update.fraction,
                        update.currentPath,
                        update.processedBytes,
                        update.totalBytes
                    )
                }
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
                progress: { update in
                    progress(
                        update.fraction,
                        update.currentPath,
                        update.processedBytes,
                        update.totalBytes
                    )
                }
            )
            return ArchiveXPCResponse(
                outputPath: summary.outputURL.path,
                addedEntries: summary.addedEntries,
                inputBytes: summary.inputBytes
            )

        case .test:
            try ArchiveService.testArchive(at: try archiveURL(request), password: request.password)
            progress(1, "完整性测试通过", 0, 0)
            return ArchiveXPCResponse()

        case .add:
            progress(0.1, "正在添加归档条目…", 0, 0)
            let summary = try ArchiveEditingService.addFiles(
                to: try archiveURL(request),
                fileURLs: request.inputPaths.map(URL.init(fileURLWithPath:)),
                password: request.password,
                cancellationToken: token
            )
            progress(1, "归档条目已添加", 0, 0)
            return ArchiveXPCResponse(changedEntries: summary.changedEntries)

        case .replace:
            progress(0.1, "正在替换归档条目…", 0, 0)
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
            progress(1, "归档条目已替换", 0, 0)
            return ArchiveXPCResponse(changedEntries: summary.changedEntries)

        case .delete:
            progress(0.1, "正在删除归档条目…", 0, 0)
            let summary = try ArchiveEditingService.deleteEntries(
                from: try archiveURL(request),
                paths: request.selectedPaths ?? [],
                password: request.password,
                cancellationToken: token
            )
            progress(1, "归档条目已删除", 0, 0)
            return ArchiveXPCResponse(changedEntries: summary.changedEntries)

        case .preview:
            progress(0.1, "正在提取预览文件…", 0, 0)
            let result = try ArchivePreviewService.extractEntry(
                archiveURL: try archiveURL(request),
                entryPath: request.entryPath ?? "",
                password: request.password,
                filenameEncoding: request.filenameEncoding,
                workingDirectory: request.destinationPath.map(URL.init(fileURLWithPath:)),
                cancellationToken: token
            )
            progress(1, "预览文件已准备", 0, 0)
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
                progress: { fraction, path in
                    progress(fraction, path, 0, 0)
                }
            )
            progress(1, "ZIP 修复副本已创建", 0, 0)
            return ArchiveXPCResponse(
                outputPath: summary.outputURL.path,
                skippedEntries: summary.skippedEntries,
                recoveredFiles: summary.recoveredFiles
            )
        }
    }

    private func validateAccess(for request: ArchiveXPCRequest) throws {
        guard request.operation != .ping else { return }
        guard let stagingRootPath = request.stagingRootPath, !stagingRootPath.isEmpty else {
            throw XPCSecurityError.unauthorizedPath("staging-root")
        }
        let stagingRoot = URL(fileURLWithPath: stagingRootPath).standardizedFileURL.path
        func authorize(_ path: String?, write: Bool = false) throws {
            guard let path else { return }
            let target = URL(fileURLWithPath: path).standardizedFileURL.path
            let rootPrefix = stagingRoot.hasSuffix("/") ? stagingRoot : stagingRoot + "/"
            guard target == stagingRoot || target.hasPrefix(rootPrefix) else {
                throw XPCSecurityError.unauthorizedPath(path)
            }
        }

        switch request.operation {
        case .ping:
            return
        case .list, .test:
            try authorize(request.archivePath)
            try preflightRead(try archiveURL(request))
        case .extract:
            try authorize(request.archivePath)
            try authorize(request.destinationPath, write: true)
            try preflightRead(try archiveURL(request))
        case .compress:
            for path in request.inputPaths { try authorize(path) }
            try authorize(request.destinationPath, write: true)
        case .add:
            try authorize(request.archivePath, write: true)
            for path in request.inputPaths { try authorize(path) }
        case .replace:
            try authorize(request.archivePath, write: true)
            for replacement in request.replacements { try authorize(replacement.sourcePath) }
        case .delete:
            try authorize(request.archivePath, write: true)
        case .preview, .repair:
            try authorize(request.archivePath)
            try authorize(request.destinationPath, write: true)
            try preflightRead(try archiveURL(request))
        }
    }

    private func preflightRead(_ url: URL) throws {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            _ = try handle.read(upToCount: 4)
        } catch {
            throw XPCSecurityError.inaccessibleGrant("preflight \(url.path): \(error.localizedDescription)")
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
        guard connection.effectiveUserIdentifier == getuid() else {
            NSLog("NanZipXPC rejected client from a different user")
            return false
        }
        do {
            let requirement = try ClientIdentityValidator.requirementForCurrentService()
            connection.setCodeSigningRequirement(requirement)
        } catch {
            NSLog("NanZipXPC client validation setup failed: \(error.localizedDescription)")
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: NanZipXPCProtocol.self)
        connection.exportedObject = service
        connection.remoteObjectInterface = NSXPCInterface(with: NanZipXPCProgressProtocol.self)
        connection.resume()
        NSLog("NanZipXPC accepted signed client pid=\(connection.processIdentifier)")
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
