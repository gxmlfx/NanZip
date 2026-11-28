import Foundation
import XCTest
@testable import NanZipCore

final class ArchiveCoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard ProcessInfo.processInfo.environment["NANZIP_7ZZ"] != nil else {
            throw XCTSkip("NANZIP_7ZZ must point to the bundled 7zz engine")
        }
    }

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testRealFixturesListAndExtract() throws {
        for fixture in ["unicode.zip", "unicode.7z", "unicode.tar.gz"] {
            let archive = try fixtureURL(fixture)
            let items = try ArchiveService.listArchive(at: archive, password: nil)
            XCTAssertTrue(items.contains { $0.path.contains("测试.txt") }, fixture)
            XCTAssertTrue(items.contains { $0.path.contains("hello.txt") }, fixture)

            let destination = try makeTemporaryDirectory()
            _ = try ArchiveService.extract(
                archiveURL: archive,
                destinationURL: destination,
                selectedPaths: nil,
                totalBytes: 0,
                password: nil,
                overwritePolicy: .overwrite,
                cancellationToken: CancellationToken(),
                progress: { _ in }
            )
            XCTAssertTrue(findFile(named: "测试.txt", below: destination) != nil, fixture)
        }
    }

    func testGBKCodePageDecoding() throws {
        let archive = try fixtureURL("gbk.zip")
        let items = try ArchiveService.listArchive(
            at: archive,
            password: nil,
            filenameEncoding: .cp936
        )
        XCTAssertEqual(items.first?.path, "中文.txt")

        let destination = try makeTemporaryDirectory()
        _ = try ArchiveService.extract(
            archiveURL: archive,
            destinationURL: destination,
            selectedPaths: nil,
            totalBytes: 0,
            password: nil,
            overwritePolicy: .overwrite,
            filenameEncoding: .cp936,
            cancellationToken: CancellationToken(),
            progress: { _ in }
        )
        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("中文.txt"), encoding: .utf8),
            "GBK fixture\n"
        )
    }

    func testCompressionAndSplitVolumeRoundTrip() throws {
        let input = try makeTemporaryDirectory().appendingPathComponent("input", isDirectory: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        var bytes = [UInt8](repeating: 0, count: 2 * 1024 * 1024)
        var state: UInt32 = 0x1234_5678
        for index in bytes.indices {
            state = state &* 1_664_525 &+ 1_013_904_223
            bytes[index] = UInt8(truncatingIfNeeded: state >> 16)
        }
        try Data(bytes).write(to: input.appendingPathComponent("payload.bin"))

        let split = try makeTemporaryDirectory().appendingPathComponent("roundtrip.zip")
        let summary = try CompressionService.createArchive(
            inputURLs: [input],
            destinationURL: split,
            options: CompressionOptions(
                format: .zip,
                level: .fast,
                volumeSizeBytes: 1 * 1024 * 1024
            ),
            cancellationToken: CancellationToken(),
            progress: { _ in }
        )
        XCTAssertEqual(summary.outputURL.pathExtension, "001")
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.outputURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.outputURL.path + ".002") == false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.outputURL.deletingLastPathComponent()
            .appendingPathComponent("roundtrip.zip.002").path))

        let items = try ArchiveService.listArchive(at: summary.outputURL, password: nil)
        XCTAssertTrue(items.contains { $0.name == "payload.bin" })
    }

    func testSkipAndOverwritePolicies() throws {
        let archive = try fixtureURL("unicode.zip")
        let destination = try makeTemporaryDirectory()
        let existing = destination.appendingPathComponent("sub/hello.txt")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: existing)

        _ = try ArchiveService.extract(
            archiveURL: archive,
            destinationURL: destination,
            selectedPaths: nil,
            totalBytes: 0,
            password: nil,
            overwritePolicy: .skip,
            cancellationToken: CancellationToken(),
            progress: { _ in }
        )
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "existing")

        _ = try ArchiveService.extract(
            archiveURL: archive,
            destinationURL: destination,
            selectedPaths: nil,
            totalBytes: 0,
            password: nil,
            overwritePolicy: .overwrite,
            cancellationToken: CancellationToken(),
            progress: { _ in }
        )
        XCTAssertNotEqual(try String(contentsOf: existing, encoding: .utf8), "existing")
    }

    func testZIPRepairFromMissingCentralDirectory() throws {
        let source = try fixtureURL("unicode.zip")
        let data = try Data(contentsOf: source)
        let centralRange = data.range(of: Data([0x50, 0x4B, 0x01, 0x02]))
        let broken = try makeTemporaryDirectory().appendingPathComponent("broken.zip")
        XCTAssertNoThrow(try data.prefix(centralRange!.lowerBound).write(to: broken))

        let repaired = broken.deletingLastPathComponent().appendingPathComponent("repaired.zip")
        let summary = try ArchiveRepairService.repairZIP(
            archiveURL: broken,
            destinationURL: repaired,
            filenameEncoding: .automatic,
            password: nil,
            cancellationToken: CancellationToken(),
            progress: { _, _ in }
        )
        XCTAssertGreaterThan(summary.recoveredFiles, 0)
        let items = try ArchiveService.listArchive(at: repaired, password: nil)
        XCTAssertFalse(items.isEmpty)
    }

    func testXPCRequestCodableStagingContract() throws {
        let request = ArchiveXPCRequest(
            operation: .extract,
            archivePath: "/Users/Shared/NanZip/XPCStaging/op/archive.zip",
            destinationPath: "/Users/Shared/NanZip/XPCStaging/op/output",
            stagingRootPath: "/Users/Shared/NanZip/XPCStaging/op"
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ArchiveXPCRequest.self, from: data)
        XCTAssertEqual(decoded.stagingRootPath, request.stagingRootPath)
        XCTAssertEqual(decoded.operation, .extract)
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let url = Bundle.module.url(
            forResource: (name as NSString).deletingPathExtension,
            withExtension: (name as NSString).pathExtension,
            subdirectory: "Fixtures"
        )
        return try XCTUnwrap(url)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nanzip-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func findFile(named name: String, below directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == name {
            return url
        }
        return nil
    }
}

private extension ArchiveOverwritePolicy {
    // Keep the test call site readable while using the core type.
    static let skipForTest: ArchiveOverwritePolicy = .skip
}
