import Compression
import Foundation

public struct ArchiveRepairSummary: Sendable {
    public let recoveredFiles: Int
    public let skippedEntries: Int
    public let outputURL: URL

    public init(recoveredFiles: Int, skippedEntries: Int, outputURL: URL) {
        self.recoveredFiles = recoveredFiles
        self.skippedEntries = skippedEntries
        self.outputURL = outputURL
    }
}

public enum ArchiveRepairError: LocalizedError {
    case sameDestination
    case notZIP
    case noRecoverableEntries
    case encryptedZIP

    public var errorDescription: String? {
        switch self {
        case .sameDestination:
            return "修复结果必须保存为新文件，不能覆盖原压缩包。"
        case .notZIP:
            return "当前安全修复仅支持 ZIP。其他格式请先保留原文件并尝试用 7-Zip 测试。"
        case .noRecoverableEntries:
            return "扫描 ZIP 本地文件头后没有找到可恢复的文件。"
        case .encryptedZIP:
            return "加密 ZIP 无法通过中央目录损坏后的原始扫描安全恢复。"
        }
    }
}

public enum ArchiveRepairService {
    public static func repairZIP(
        archiveURL: URL,
        destinationURL: URL,
        filenameEncoding: ArchiveFilenameEncoding,
        password: String?,
        cancellationToken: CancellationToken,
        progress: @escaping @Sendable (Double, String) -> Void
    ) throws -> ArchiveRepairSummary {
        guard archiveURL.standardizedFileURL != destinationURL.standardizedFileURL else {
            throw ArchiveRepairError.sameDestination
        }
        guard archiveURL.pathExtension.lowercased() == "zip" else {
            throw ArchiveRepairError.notZIP
        }

        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory
            .appendingPathComponent("nanzip-repair-\(UUID().uuidString)", isDirectory: true)
        let recoveredRoot = work.appendingPathComponent("recovered", isDirectory: true)
        try fileManager.createDirectory(at: recoveredRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: work) }

        progress(0.05, "正在读取 ZIP 本地文件头…")
        let data = try Data(contentsOf: archiveURL, options: [.mappedIfSafe])
        let entries = scanLocalHeaders(in: data, encoding: filenameEncoding)
        var recovered = 0
        var skipped = 0

        for (index, entry) in entries.enumerated() {
            if cancellationToken.isCancelled { throw ArchiveError.cancelled }
            if entry.isEncrypted {
                throw ArchiveRepairError.encryptedZIP
            }
            guard let relativePath = safeRelativePath(entry.path) else {
                skipped += 1
                continue
            }
            do {
                let payload = try compressedPayload(for: entry, in: data)
                let output: Data
                switch entry.method {
                case 0:
                    output = payload
                case 8:
                    output = try inflateRawDeflate(payload)
                default:
                    skipped += 1
                    continue
                }
                let target = recoveredRoot.appendingPathComponent(relativePath)
                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try output.write(to: target, options: .atomic)
                recovered += 1
            } catch {
                skipped += 1
            }
            let fraction = entries.isEmpty ? 0.7 : 0.1 + Double(index + 1) / Double(entries.count) * 0.6
            progress(fraction, "正在恢复 \(entry.path)")
        }

        guard recovered > 0 else {
            throw ArchiveRepairError.noRecoverableEntries
        }

        let topLevelURLs = try fileManager.contentsOfDirectory(
            at: recoveredRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        progress(0.75, "正在重建全新的 ZIP 压缩包…")
        let summary = try CompressionService.createArchive(
            inputURLs: topLevelURLs,
            destinationURL: destinationURL,
            options: CompressionOptions(
                format: .zip,
                level: .balanced,
                password: password,
                filenameEncoding: filenameEncoding
            ),
            cancellationToken: cancellationToken
        ) { update in
            progress(0.75 + update.fraction * 0.25, update.currentPath)
        }
        return ArchiveRepairSummary(
            recoveredFiles: recovered,
            skippedEntries: skipped,
            outputURL: summary.outputURL
        )
    }

    private struct LocalEntry {
        let path: String
        let flags: UInt16
        let method: UInt16
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let dataStart: Int
        let nextBoundary: Int

        var isEncrypted: Bool { flags & 0x0001 != 0 }
    }

    private static func scanLocalHeaders(
        in data: Data,
        encoding: ArchiveFilenameEncoding
    ) -> [LocalEntry] {
        let signature = Data([0x50, 0x4B, 0x03, 0x04])
        let centralSignature = Data([0x50, 0x4B, 0x01, 0x02])
        let endSignature = Data([0x50, 0x4B, 0x05, 0x06])
        var entries: [LocalEntry] = []
        var searchStart = data.startIndex

        while searchStart < data.endIndex,
              let headerRange = data.range(of: signature, options: [], in: searchStart..<data.endIndex) {
            let offset = headerRange.lowerBound
            guard offset + 30 <= data.endIndex else { break }
            let flags = readUInt16(data, offset + 6)
            let method = readUInt16(data, offset + 8)
            let compressedSize = readUInt32(data, offset + 18)
            let uncompressedSize = readUInt32(data, offset + 22)
            let nameLength = Int(readUInt16(data, offset + 26))
            let extraLength = Int(readUInt16(data, offset + 28))
            let nameStart = offset + 30
            let dataStart = nameStart + nameLength + extraLength
            guard nameStart + nameLength <= data.endIndex, dataStart <= data.endIndex else { break }

            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            let path = decodeFilename(nameData, flags: flags, encoding: encoding)
            let boundary = nearestArchiveBoundary(
                in: data,
                after: dataStart,
                signatures: [signature, centralSignature, endSignature]
            ) ?? data.endIndex
            entries.append(
                LocalEntry(
                    path: path,
                    flags: flags,
                    method: method,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    dataStart: dataStart,
                    nextBoundary: boundary
                )
            )
            searchStart = max(boundary, headerRange.upperBound)
        }
        return entries
    }

    private static func nearestArchiveBoundary(
        in data: Data,
        after start: Int,
        signatures: [Data]
    ) -> Int? {
        signatures.compactMap { signature in
            data.range(of: signature, options: [], in: start..<data.endIndex)?.lowerBound
        }.min()
    }

    private static func compressedPayload(for entry: LocalEntry, in data: Data) throws -> Data {
        if entry.compressedSize > 0 {
            let end = min(entry.dataStart + Int(entry.compressedSize), entry.nextBoundary)
            guard end > entry.dataStart else {
                throw ArchiveError.invalidArchive("ZIP 条目长度无效")
            }
            return data.subdata(in: entry.dataStart..<end)
        }

        var end = entry.nextBoundary
        let descriptor = Data([0x50, 0x4B, 0x07, 0x08])
        if let descriptorRange = data.range(
            of: descriptor,
            options: [],
            in: entry.dataStart..<entry.nextBoundary
        ) {
            end = descriptorRange.lowerBound
        }
        guard end > entry.dataStart else {
            throw ArchiveError.invalidArchive("ZIP 条目缺少长度描述")
        }
        return data.subdata(in: entry.dataStart..<end)
    }

    private static func inflateRawDeflate(_ compressed: Data) throws -> Data {
        guard !compressed.isEmpty else { return Data() }
        var capacity = 1 << 20
        let maximum = 1 << 30
        while capacity <= maximum {
            var output = Data(count: capacity)
            let written = output.withUnsafeMutableBytes { destination in
                compressed.withUnsafeBytes { source in
                    compression_decode_buffer(
                        destination.bindMemory(to: UInt8.self).baseAddress!,
                        capacity,
                        source.bindMemory(to: UInt8.self).baseAddress!,
                        compressed.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            if written > 0 {
                output.removeSubrange(written..<output.count)
                return output
            }
            capacity *= 2
        }
        throw ArchiveError.invalidArchive("无法解压 Deflate 数据")
    }

    private static func decodeFilename(
        _ data: Data,
        flags: UInt16,
        encoding: ArchiveFilenameEncoding
    ) -> String {
        if flags & 0x0800 != 0, let value = String(data: data, encoding: .utf8) {
            return value
        }
        if encoding != .automatic, let stringEncoding = encoding.stringEncoding,
           let value = String(data: data, encoding: stringEncoding) {
            return value
        }
        if let value = String(data: data, encoding: .utf8) {
            return value
        }
        if let value = String(data: data, encoding: .windowsCP1252) {
            return value
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func safeRelativePath(_ path: String) -> String? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/", omittingEmptySubsequences: true)
        guard !normalized.hasPrefix("/"), !components.contains("..") else { return nil }
        let cleaned = components.map { component -> String in
            let value = String(component)
            return value == "." ? "_" : value
        }.joined(separator: "/")
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) |
            UInt32(data[offset + 1]) << 8 |
            UInt32(data[offset + 2]) << 16 |
            UInt32(data[offset + 3]) << 24
    }
}
