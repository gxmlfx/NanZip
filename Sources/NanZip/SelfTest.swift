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
        case "--volume-test":
            runVolumeTest(arguments: arguments)
        case "--replace-test":
            runReplaceTest(arguments: arguments)
        case "--delete-test":
            runDeleteTest(arguments: arguments)
        case "--repair-test":
            runRepairTest(arguments: arguments)
        case "--xpc-test":
            runXPCTest(arguments: arguments)
        case "--xpc-internal-test":
            runInternalXPCTest()
        case "--xpc-ping-test":
            runXPCPingTest()
        case "--keychain-test":
            runKeychainTest()
        default:
            usage()
        }
    }

    private static func runExtractionTest(arguments: [String]) -> Never {
        guard arguments.count >= 4 else { usage() }
        let archiveURL = URL(fileURLWithPath: arguments[2])
        let destinationURL = URL(fileURLWithPath: arguments[3])
        let password = arguments.count >= 5 && arguments[4] != "-" ? arguments[4] : nil
        let encoding = arguments.count >= 6
            ? (ArchiveFilenameEncoding(rawValue: arguments[5]) ?? .automatic)
            : .automatic
        let overwritePolicy = arguments.count >= 7
            ? (ArchiveOverwritePolicy(rawValue: arguments[6]) ?? .keepBoth)
            : .keepBoth
        do {
            let listRequest = ArchiveXPCRequest(
                operation: .list,
                archivePath: archiveURL.path,
                password: password,
                filenameEncoding: encoding
            )
            let items = try ArchiveOperationBridge.list(listRequest)
            let totalBytes = items.reduce(Int64(0)) { $0 + ($1.isDirectory ? 0 : $1.size) }
            let extractRequest = ArchiveXPCRequest(
                operation: .extract,
                archivePath: archiveURL.path,
                destinationPath: destinationURL.path,
                password: password,
                overwritePolicy: overwritePolicy,
                filenameEncoding: encoding
            )
            let summary = try ArchiveOperationBridge.extract(extractRequest)
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
            let request = ArchiveXPCRequest(
                operation: .compress,
                destinationPath: destinationURL.path,
                inputPaths: inputURLs.map(\.path),
                password: options.password,
                compressionOptions: options
            )
            let summary = try ArchiveOperationBridge.compress(
                request,
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

    private static func runVolumeTest(arguments: [String]) -> Never {
        guard arguments.count >= 7 else { usage() }
        let formatRaw = arguments[2]
        let destinationURL = URL(fileURLWithPath: arguments[3])
        let levelRaw = Int(arguments[4]) ?? 6
        let password = arguments[5] == "-" ? nil : arguments[5]
        let volumeMB = Int64(arguments[6]) ?? 1
        let inputURLs = arguments.dropFirst(7).map { URL(fileURLWithPath: $0) }
        guard let format = CompressionFormat(rawValue: formatRaw),
              let level = CompressionLevel(rawValue: levelRaw) else {
            usage()
        }

        let options = CompressionOptions(
            format: format,
            level: level,
            password: password,
            volumeSizeBytes: max(volumeMB, 1) * 1_024 * 1_024
        )
        let token = CancellationToken()
        do {
            let request = ArchiveXPCRequest(
                operation: .compress,
                destinationPath: destinationURL.path,
                inputPaths: inputURLs.map(\.path),
                password: options.password,
                compressionOptions: options
            )
            let summary = try ArchiveOperationBridge.compress(
                request,
                cancellationToken: token,
                progress: { _ in }
            )
            let items = try ArchiveOperationBridge.list(
                ArchiveXPCRequest(operation: .list, archivePath: summary.outputURL.path, password: password)
            )
            print("entries=\(summary.addedEntries)")
            print("listed=\(items.count)")
            print("output=\(summary.outputURL.path)")
            exit(0)
        } catch {
            fail(error)
        }
    }

    private static func runReplaceTest(arguments: [String]) -> Never {
        guard arguments.count >= 6 else { usage() }
        let archiveURL = URL(fileURLWithPath: arguments[2])
        let archivePath = arguments[3]
        let sourceURL = URL(fileURLWithPath: arguments[4])
        let password = arguments[5] == "-" ? nil : arguments[5]
        let token = CancellationToken()
        do {
            let request = ArchiveXPCRequest(
                operation: .replace,
                archivePath: archiveURL.path,
                password: password,
                replacements: [ArchiveXPCReplacement(archivePath: archivePath, sourcePath: sourceURL.path)]
            )
            let changed = try ArchiveOperationBridge.edit(request, cancellationToken: token)
            let summary = ArchiveEditSummary(changedEntries: changed, archiveURL: archiveURL)
            let items = try ArchiveOperationBridge.list(
                ArchiveXPCRequest(operation: .list, archivePath: archiveURL.path, password: password)
            )
            print("changed=\(summary.changedEntries)")
            print("items=\(items.count)")
            print("archive=\(archiveURL.path)")
            exit(0)
        } catch {
            fail(error)
        }
    }

    private static func runDeleteTest(arguments: [String]) -> Never {
        guard arguments.count >= 5 else { usage() }
        let archiveURL = URL(fileURLWithPath: arguments[2])
        let archivePath = arguments[3]
        let password = arguments[4] == "-" ? nil : arguments[4]
        let token = CancellationToken()
        do {
            let request = ArchiveXPCRequest(
                operation: .delete,
                archivePath: archiveURL.path,
                selectedPaths: [archivePath],
                password: password
            )
            let changed = try ArchiveOperationBridge.edit(request, cancellationToken: token)
            let summary = ArchiveEditSummary(changedEntries: changed, archiveURL: archiveURL)
            print("changed=\(summary.changedEntries)")
            exit(0)
        } catch {
            fail(error)
        }
    }

    private static func runRepairTest(arguments: [String]) -> Never {
        guard arguments.count >= 5 else { usage() }
        let archiveURL = URL(fileURLWithPath: arguments[2])
        let destinationURL = URL(fileURLWithPath: arguments[3])
        let password = arguments[4] == "-" ? nil : arguments[4]
        do {
            let options = CompressionOptions(
                format: .zip,
                level: .balanced,
                password: password,
                filenameEncoding: .automatic
            )
            let request = ArchiveXPCRequest(
                operation: .repair,
                archivePath: archiveURL.path,
                destinationPath: destinationURL.path,
                password: password,
                compressionOptions: options
            )
            let summary = try ArchiveOperationBridge.repair(
                request,
                cancellationToken: CancellationToken(),
                progress: { _, _ in }
            )
            let items = try ArchiveOperationBridge.list(
                ArchiveXPCRequest(operation: .list, archivePath: destinationURL.path, password: password)
            )
            print("recovered=\(summary.recoveredFiles)")
            print("skipped=\(summary.skippedEntries)")
            print("items=\(items.count)")
            print("output=\(summary.outputURL.path)")
            exit(0)
        } catch {
            fail(error)
        }
    }

    private static func runXPCTest(arguments: [String]) -> Never {
        guard arguments.count >= 3 else { usage() }
        let archiveURL = URL(fileURLWithPath: arguments[2])
        do {
            let listResponse = try ArchiveXPCClient.shared.perform(
                ArchiveXPCRequest(operation: .list, archivePath: archiveURL.path)
            )
            let items = listResponse.items ?? []
            print("items=\(items.count)")
            if arguments.count >= 4 {
                let destination = URL(fileURLWithPath: arguments[3])
                let extractResponse = try ArchiveXPCClient.shared.perform(
                    ArchiveXPCRequest(
                        operation: .extract,
                        archivePath: archiveURL.path,
                        destinationPath: destination.path
                    )
                )
                print("extracted=\(extractResponse.extractedFiles ?? 0)")
            }
            exit(0)
        } catch {
            fail(error)
        }
    }

    private static func runXPCPingTest() -> Never {
        guard ArchiveXPCClient.shared.ping() else {
            fail(ArchiveXPCClientError.unavailable)
        }
        print("xpc-ping=PASS")
        exit(0)
    }

    private static func runInternalXPCTest() -> Never {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("nanzip-internal-xpc-\(UUID().uuidString)")
        let archive = root.appendingPathComponent("internal.zip")
        let destination = root.appendingPathComponent("out", isDirectory: true)
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            let encodedZIP = "UEsDBBQAAAAAAAAAAAA4LHJ8DAAAAAwAAAAJAAAAaGVsbG8udHh0aW50ZXJuYWwteHBjUEsBAhQAFAAAAAAAAAAAADgscnwMAAAADAAAAAkAAAAAAAAAAAAAAAAAAAAAAGhlbGxvLnR4dFBLBQYAAAAAAQABADcAAAAzAAAAAAA="
            guard let archiveData = Data(base64Encoded: encodedZIP) else {
                throw ArchiveError.fileSystem("无法构造内部 ZIP fixture。")
            }
            try archiveData.write(to: archive)
            let client = ArchiveXPCClient.shared
            let progressLock = NSLock()
            var progressEvents = 0
            let listed = try client.perform(
                ArchiveXPCRequest(operation: .list, archivePath: archive.path),
                progress: { _ in
                    progressLock.lock()
                    progressEvents += 1
                    progressLock.unlock()
                }
            ).items
            progressLock.lock()
            let observedProgress = progressEvents
            progressLock.unlock()
            guard listed?.isEmpty == false, observedProgress > 1 else {
                throw ArchiveError.invalidArchive("XPC 内部测试列表为空。")
            }
            let input = root.appendingPathComponent("input.txt")
            try Data("xpc-compress".utf8).write(to: input)
            let compressed = root.appendingPathComponent("generated.zip")
            _ = try client.perform(
                ArchiveXPCRequest(
                    operation: .compress,
                    destinationPath: compressed.path,
                    inputPaths: [input.path],
                    compressionOptions: CompressionOptions(format: .zip, level: .balanced)
                )
            )
            guard fileManager.fileExists(atPath: compressed.path) else {
                throw ArchiveError.fileSystem("XPC 内部压缩没有生成文件。")
            }
            _ = try client.perform(
                ArchiveXPCRequest(
                    operation: .extract,
                    archivePath: archive.path,
                    destinationPath: destination.path
                )
            )
            print("xpc-internal=PASS progress_events=\(observedProgress)")
            try? fileManager.removeItem(at: root)
            exit(0)
        } catch {
            try? fileManager.removeItem(at: root)
            fail(error)
        }
    }

    private static func runKeychainTest() -> Never {
        let archiveURL = URL(fileURLWithPath: "/tmp/nanzip-keychain-test-\(UUID().uuidString).zip")
        let password = "nanzip-keychain-\(UUID().uuidString)"
        do {
            try PasswordStore.save(password: password, for: archiveURL)
            guard PasswordStore.password(for: archiveURL) == password else {
                throw ArchiveError.fileSystem("Keychain 密码读回不一致。")
            }
            guard PasswordStore.allArchiveAccounts().contains(PasswordStore.accountKey(for: archiveURL)) else {
                throw ArchiveError.fileSystem("Keychain 列表中没有测试账户。")
            }
            try PasswordStore.deletePassword(for: archiveURL)
            guard PasswordStore.password(for: archiveURL) == nil else {
                throw ArchiveError.fileSystem("Keychain 测试账户未删除。")
            }
            print("keychain=PASS")
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
          NanZip --self-test <archive> <destination> [password|-] [encoding] [overwrite]
          NanZip --compress-test <format> <output> <level> <password|-> <input>...
          NanZip --volume-test <format> <output> <level> <password|-> <volume-mb> <input>...
          NanZip --replace-test <archive> <archive-path> <source> <password|->
          NanZip --delete-test <archive> <archive-path> <password|->
          NanZip --repair-test <archive.zip> <new-output.zip> <password|->
          NanZip --xpc-test <archive> [destination]
          NanZip --xpc-internal-test
          NanZip --xpc-ping-test
          NanZip --keychain-test
        Formats: zip, sevenZip, tar, tarGz, tarBz2, tarXz
        """.utf8))
        exit(2)
    }
}
