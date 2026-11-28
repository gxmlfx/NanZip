import Foundation
import NanZipCore

enum ArchiveOperationBridge {
    static var hasEmbeddedXPCService: Bool {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return false }
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/XPCServices/NanZipXPCService.xpc")
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func list(_ request: ArchiveXPCRequest) throws -> [ArchiveItem] {
        if hasEmbeddedXPCService {
            do {
                return try ArchiveXPCClient.shared.perform(request).items ?? []
            } catch ArchiveXPCClientError.unavailable {
                // CLI and non-standard launch contexts can still use the local engine.
            }
        }
        return try ArchiveService.listArchive(
            at: try archiveURL(request),
            password: request.password,
            filenameEncoding: request.filenameEncoding
        )
    }

    static func extract(
        _ request: ArchiveXPCRequest,
        progress: @escaping @Sendable (ExtractionProgress) -> Void = { _ in }
    ) throws -> ExtractionSummary {
        if hasEmbeddedXPCService {
            do {
                let response = try ArchiveXPCClient.shared.perform(
                    request,
                    progress: { event in
                        progress(
                            ExtractionProgress(
                                fraction: event.fraction,
                                currentPath: event.currentPath,
                                processedBytes: event.processedBytes,
                                totalBytes: event.totalBytes
                            )
                        )
                    }
                )
                return ExtractionSummary(
                    extractedFiles: response.extractedFiles ?? 0,
                    skippedEntries: response.skippedEntries ?? 0
                )
            } catch ArchiveXPCClientError.unavailable {
            }
        }
        return try ArchiveService.extract(
            archiveURL: try archiveURL(request),
            destinationURL: try destinationURL(request),
            selectedPaths: request.selectedPaths,
            totalBytes: 0,
            password: request.password,
            overwritePolicy: request.overwritePolicy,
            filenameEncoding: request.filenameEncoding,
            cancellationToken: CancellationToken(),
            progress: progress
        )
    }

    static func compress(
        _ request: ArchiveXPCRequest,
        cancellationToken: CancellationToken,
        progress: @escaping @Sendable (CompressionProgress) -> Void
    ) throws -> CompressionSummary {
        if hasEmbeddedXPCService {
            do {
                let response = try ArchiveXPCClient.shared.perform(
                    request,
                    progress: { event in
                        progress(
                            CompressionProgress(
                                fraction: event.fraction,
                                currentPath: event.currentPath,
                                processedBytes: event.processedBytes,
                                totalBytes: event.totalBytes
                            )
                        )
                    }
                )
                guard let outputPath = response.outputPath else {
                    throw ArchiveXPCClientError.invalidResponse
                }
                return CompressionSummary(
                    addedEntries: response.addedEntries ?? 0,
                    inputBytes: response.inputBytes ?? 0,
                    outputURL: URL(fileURLWithPath: outputPath)
                )
            } catch ArchiveXPCClientError.unavailable {
            }
        }
        guard let options = request.compressionOptions else {
            throw ArchiveError.fileSystem("压缩参数缺失。")
        }
        return try CompressionService.createArchive(
            inputURLs: request.inputPaths.map(URL.init(fileURLWithPath:)),
            destinationURL: try destinationURL(request),
            options: options,
            cancellationToken: cancellationToken,
            progress: progress
        )
    }

    static func test(_ request: ArchiveXPCRequest) throws {
        if hasEmbeddedXPCService {
            do {
                _ = try ArchiveXPCClient.shared.perform(request)
                return
            } catch ArchiveXPCClientError.unavailable {
            }
        }
        try ArchiveService.testArchive(at: try archiveURL(request), password: request.password)
    }

    static func edit(
        _ request: ArchiveXPCRequest,
        cancellationToken: CancellationToken
    ) throws -> Int {
        if hasEmbeddedXPCService {
            do {
                return try ArchiveXPCClient.shared.perform(request).changedEntries ?? 0
            } catch ArchiveXPCClientError.unavailable {
            }
        }
        switch request.operation {
        case .add:
            return try ArchiveEditingService.addFiles(
                to: try archiveURL(request),
                fileURLs: request.inputPaths.map(URL.init(fileURLWithPath:)),
                password: request.password,
                cancellationToken: cancellationToken
            ).changedEntries
        case .replace:
            return try ArchiveEditingService.replaceEntries(
                in: try archiveURL(request),
                replacements: request.replacements.map {
                    ArchiveReplacement(
                        archivePath: $0.archivePath,
                        sourceURL: URL(fileURLWithPath: $0.sourcePath)
                    )
                },
                password: request.password,
                cancellationToken: cancellationToken
            ).changedEntries
        case .delete:
            return try ArchiveEditingService.deleteEntries(
                from: try archiveURL(request),
                paths: request.selectedPaths ?? [],
                password: request.password,
                cancellationToken: cancellationToken
            ).changedEntries
        default:
            throw ArchiveError.fileSystem("不支持的归档编辑操作。")
        }
    }

    static func preview(
        _ request: ArchiveXPCRequest,
        cancellationToken: CancellationToken
    ) throws -> ArchivePreviewResult {
        if hasEmbeddedXPCService {
            do {
                let response = try ArchiveXPCClient.shared.perform(request)
                guard let output = response.outputPath,
                      let working = response.previewWorkingDirectory else {
                    throw ArchiveXPCClientError.invalidResponse
                }
                return ArchivePreviewResult(
                    extractedURL: URL(fileURLWithPath: output),
                    workingDirectoryURL: URL(fileURLWithPath: working)
                )
            } catch ArchiveXPCClientError.unavailable {
            }
        }
        return try ArchivePreviewService.extractEntry(
            archiveURL: try archiveURL(request),
            entryPath: request.entryPath ?? "",
            password: request.password,
            filenameEncoding: request.filenameEncoding,
            workingDirectory: request.destinationPath.map(URL.init(fileURLWithPath:)),
            cancellationToken: cancellationToken
        )
    }

    static func repair(
        _ request: ArchiveXPCRequest,
        cancellationToken: CancellationToken,
        progress: @escaping @Sendable (Double, String) -> Void
    ) throws -> ArchiveRepairSummary {
        if hasEmbeddedXPCService {
            do {
                let response = try ArchiveXPCClient.shared.perform(
                    request,
                    progress: { event in
                        progress(event.fraction, event.currentPath)
                    }
                )
                guard let output = response.outputPath else {
                    throw ArchiveXPCClientError.invalidResponse
                }
                return ArchiveRepairSummary(
                    recoveredFiles: response.recoveredFiles ?? 0,
                    skippedEntries: response.skippedEntries ?? 0,
                    outputURL: URL(fileURLWithPath: output)
                )
            } catch ArchiveXPCClientError.unavailable {
            }
        }
        return try ArchiveRepairService.repairZIP(
            archiveURL: try archiveURL(request),
            destinationURL: try destinationURL(request),
            filenameEncoding: request.compressionOptions?.filenameEncoding ?? .automatic,
            password: request.password,
            cancellationToken: cancellationToken,
            progress: progress
        )
    }

    private static func archiveURL(_ request: ArchiveXPCRequest) throws -> URL {
        guard let path = request.archivePath else {
            throw ArchiveError.fileSystem("归档路径缺失。")
        }
        return URL(fileURLWithPath: path)
    }

    private static func destinationURL(_ request: ArchiveXPCRequest) throws -> URL {
        guard let path = request.destinationPath else {
            throw ArchiveError.fileSystem("目标路径缺失。")
        }
        return URL(fileURLWithPath: path)
    }
}
