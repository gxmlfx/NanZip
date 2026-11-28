import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct SevenZipRunResult: Sendable {
    public let standardOutput: String
    public let standardError: String
    public let exitCode: Int32
}

public enum SevenZipError: LocalizedError {
    case engineNotFound
    case launchFailed(String)
    case processFailed(code: Int32, message: String)
    case passphraseRequired
    case invalidArchive(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .engineNotFound:
            return "找不到随应用打包的 7-Zip 引擎。"
        case .launchFailed(let message):
            return "无法启动 7-Zip 引擎：\(message)"
        case .processFailed(let code, let message):
            return message == "7-Zip 执行失败" ? "7-Zip 执行失败（exit \(code)）" : message
        case .passphraseRequired:
            return "该压缩包已加密，请输入正确密码后重试。"
        case .invalidArchive(let message):
            return "压缩包格式无效或已损坏：\(message)"
        case .cancelled:
            return "操作已取消。"
        }
    }
}

public enum SevenZipEngine {
    public static func executableURL() throws -> URL {
        var candidates: [URL] = []

        if let override = ProcessInfo.processInfo.environment["NANZIP_7ZZ"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }

        let mainBundle = Bundle.main.bundleURL
        candidates.append(mainBundle.appendingPathComponent("Contents/Resources/Helpers/7zz"))
        candidates.append(mainBundle.appendingPathComponent("Resources/Helpers/7zz"))
        candidates.append(mainBundle.deletingLastPathComponent().appendingPathComponent("Resources/Helpers/7zz"))

        let extensionHost = mainBundle
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        candidates.append(extensionHost.appendingPathComponent("Contents/Resources/Helpers/7zz"))
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/7zz"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/7zz"))

        let fileManager = FileManager.default
        for candidate in candidates {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  fileManager.isExecutableFile(atPath: candidate.path) else {
                continue
            }
            return candidate
        }

        throw SevenZipError.engineNotFound
    }

    public static func run(
        arguments: [String],
        workingDirectory: URL? = nil,
        cancellationToken: CancellationToken? = nil,
        progress: (@Sendable (Double, String) -> Void)? = nil
    ) throws -> SevenZipRunResult {
        let executable = try executableURL()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardInput = FileHandle.nullDevice

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputBuffer = OutputBuffer()
        let progressParser = ProgressParser(callback: progress)
        let readGroup = DispatchGroup()

        try process.run()

        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            readPipe(outputPipe.fileHandleForReading) { data in
                outputBuffer.appendStandardOutput(data)
                progressParser.consume(data)
            }
            readGroup.leave()
        }

        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            readPipe(errorPipe.fileHandleForReading) { data in
                outputBuffer.appendStandardError(data)
                progressParser.consume(data)
            }
            readGroup.leave()
        }

        let cancellationWork = DispatchWorkItem {
            while process.isRunning {
                if cancellationToken?.isCancelled == true {
                    process.terminate()
                    return
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        DispatchQueue.global(qos: .utility).async(execute: cancellationWork)

        process.waitUntilExit()
        cancellationWork.cancel()
        readGroup.wait()

        if cancellationToken?.isCancelled == true {
            throw SevenZipError.cancelled
        }

        let result = SevenZipRunResult(
            standardOutput: outputBuffer.standardOutput,
            standardError: outputBuffer.standardError,
            exitCode: process.terminationStatus
        )

        if result.exitCode <= 1 {
            return result
        }

        throw classifyFailure(result)
    }

    public static func classifyFailure(_ result: SevenZipRunResult) -> Error {
        let combined = "\(result.standardOutput)\n\(result.standardError)"
        let lowercased = combined.lowercased()
        if lowercased.contains("wrong password") ||
            lowercased.contains("password is incorrect") ||
            lowercased.contains("enter password") ||
            lowercased.contains("can not open encrypted archive") ||
            lowercased.contains("cannot open encrypted archive") {
            return SevenZipError.passphraseRequired
        }
        if lowercased.contains("can not open the file as archive") ||
            lowercased.contains("cannot open the file as archive") ||
            lowercased.contains("is not archive") ||
            lowercased.contains("unexpected end of archive") ||
            lowercased.contains("data error") {
            return SevenZipError.invalidArchive(shortMessage(from: combined))
        }
        return SevenZipError.processFailed(
            code: result.exitCode,
            message: shortMessage(from: combined)
        )
    }

    private static func shortMessage(from output: String) -> String {
        let lines = output
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let relevant = lines.last(where: {
            let lower = $0.lowercased()
            return lower.contains("error") || lower.contains("wrong") || lower.contains("can not") ||
                lower.contains("cannot") || lower.contains("not archive") || lower.contains("unsupported")
        })
        return relevant ?? lines.last ?? "7-Zip 执行失败"
    }

    private static func readPipe(_ handle: FileHandle, onData: @escaping (Data) -> Void) {
        while true {
            do {
                guard let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty else {
                    break
                }
                onData(data)
            } catch {
                break
            }
        }
        try? handle.close()
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var output = Data()
    private var error = Data()

    func appendStandardOutput(_ data: Data) {
        lock.lock()
        output.append(data)
        lock.unlock()
    }

    func appendStandardError(_ data: Data) {
        lock.lock()
        error.append(data)
        lock.unlock()
    }

    var standardOutput: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: output, encoding: .utf8) ?? ""
    }

    var standardError: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: error, encoding: .utf8) ?? ""
    }
}

private final class ProgressParser: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var lastFraction = -1.0
    private var lastPath = ""
    private let callback: (@Sendable (Double, String) -> Void)?

    init(callback: (@Sendable (Double, String) -> Void)?) {
        self.callback = callback
    }

    func consume(_ data: Data) {
        guard let callback, let text = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        buffer += text
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{8}", with: "")
        if buffer.count > 16_384 {
            buffer = String(buffer.suffix(8_192))
        }

        let pattern = #"(\d{1,3})%[^\n]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            lock.unlock()
            return
        }
        let range = NSRange(buffer.startIndex..<buffer.endIndex, in: buffer)
        let matches = regex.matches(in: buffer, range: range)
        guard let match = matches.last,
              let percentRange = Range(match.range(at: 1), in: buffer),
              let fullRange = Range(match.range(at: 0), in: buffer),
              let percent = Double(buffer[percentRange]) else {
            lock.unlock()
            return
        }

        let fraction = min(1, max(0, percent / 100))
        let line = String(buffer[fullRange])
            .replacingOccurrences(of: "\(Int(percent))%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        let shouldReport = abs(fraction - lastFraction) >= 0.005 || line != lastPath
        lastFraction = fraction
        lastPath = line
        lock.unlock()

        if shouldReport {
            callback(fraction, line)
        }
    }
}
