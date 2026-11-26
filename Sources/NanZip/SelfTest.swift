import Foundation
import NanZipCore

enum NanZipSelfTest {
    static func run() -> Never {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            usage()
        }

        switch arguments[1] {
        case "--self-test":
            runExtractionTest(arguments: arguments)
        case "--compress-test":
            runCompressionTest(arguments: arguments)
        default:
            usage()
        }
    }

    private static func runExtractionTest(arguments: [String]) -> Never {
        guard arguments.count >= 4 else { usage() }
        let archiveURL = URL(fileURLWithPath: arguments[2])
        let destinationURL = URL(fileURLWithPath: arguments[3])
        let password = arguments.count >= 5 ? arguments[4] : nil
        let token = CancellationToken()

        do {
            let items = try ArchiveService.listArchive(at: archiveURL, password: password)
            let totalBytes = items.reduce(Int64(0)) { $0 + ($1.isDirectory ? 0 : $1.size) }
            let summary = try ArchiveService.extract(
                archiveURL: archiveURL,
                destinationURL: destinationURL,
                selectedPaths: nil,
                totalBytes: totalBytes,
                password: password,
                overwritePolicy: .keepBoth,
                cancellationToken: token,
                progress: { _ in }
            )
            print("items=\(items.count)")
            print("extracted=\(summary.extractedFiles)")
            print("skipped=\(summary.skippedEntries)")
            print("bytes=\(totalBytes)")
            exit(0)
        } catch {
            fail(error)
        }
    }

    private static func runCompressionTest(arguments: [String]) -> Never {
        guard arguments.count >= 6 else { usage() }
        let formatRaw = arguments[2]
        let destinationURL = URL(fileURLWithPath: arguments[3])
        let levelRaw = Int(arguments[4]) ?? 6
        let password = arguments[5] == "-" ? nil : arguments[5]
        let inputURLs = arguments.dropFirst(6).map { URL(fileURLWithPath: $0) }
        guard let format = CompressionFormat(rawValue: formatRaw),
              let level = CompressionLevel(rawValue: levelRaw) else {
            usage()
        }

        let options = CompressionOptions(format: format, level: level, password: password)
        let token = CancellationToken()
        do {
            let summary = try CompressionService.createArchive(
                inputURLs: inputURLs,
                destinationURL: destinationURL,
                options: options,
                cancellationToken: token,
                progress: { _ in }
            )
            print("entries=\(summary.addedEntries)")
            print("bytes=\(summary.inputBytes)")
            print("output=\(summary.outputURL.path)")
            exit(0)
        } catch {
            fail(error)
        }
    }

    private static func fail(_ error: Error) -> Never {
        FileHandle.standardError.write(Data("SELF_TEST_FAILED: \(error.localizedDescription)\n".utf8))
        exit(1)
    }

    private static func usage() -> Never {
        FileHandle.standardError.write(Data("""
        Usage:
          NanZip --self-test <archive> <destination> [password]
          NanZip --compress-test <format> <output> <level> <password|-> <input>...
        Formats: zip, sevenZip, tarGz, tarBz2, tarXz
        """.utf8))
        exit(2)
    }
}
