import Foundation
import NanZipCore

enum XPCStagingError: LocalizedError {
    case missingPath(String)
    case copyFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .missingPath(let path):
            return "操作路径缺失：\(path)"
        case .copyFailed(let path, let detail):
            return "无法准备安全暂存文件：\(path)（\(detail)）"
        }
    }
}

final class XPCStagingOperation {
    private let request: ArchiveXPCRequest
    private let root: URL
    private var archiveURL: URL?
    private var destinationURL: URL?
    private var stagedArchiveURL: URL?
    private var stagedDestinationURL: URL?
    private(set) var xpcRequest: ArchiveXPCRequest

    init(request: ArchiveXPCRequest) throws {
        self.request = request
        try XPCSharedStorage.prepare()
        XPCSharedStorage.removeStaleDirectories()
        root = XPCSharedStorage.stagingRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        archiveURL = request.archivePath.map(URL.init(fileURLWithPath:))
        destinationURL = request.destinationPath.map(URL.init(fileURLWithPath:))
        stagedArchiveURL = nil
        stagedDestinationURL = nil
        xpcRequest = request

        switch request.operation {
        case .ping:
            return
        case .list, .test:
            guard let archiveURL else {
                throw XPCStagingError.missingPath("archive")
            }
            let staged = try stageArchive(archiveURL)
            stagedArchiveURL = staged
            stagedDestinationURL = nil
            xpcRequest = request
                .replacingArchivePath(staged.path)
                .replacingStagingRoot(root.path)
        case .extract:
            guard let archiveURL, self.destinationURL != nil else {
                throw XPCStagingError.missingPath("archive or destination")
            }
            let stagedArchive = try stageArchive(archiveURL)
            let stagedDestination = root.appendingPathComponent("extract", isDirectory: true)
            try FileManager.default.createDirectory(at: stagedDestination, withIntermediateDirectories: true)
            stagedArchiveURL = stagedArchive
            stagedDestinationURL = stagedDestination
            xpcRequest = request
                .replacingArchivePath(stagedArchive.path)
                .replacingDestinationPath(stagedDestination.path)
                .replacingStagingRoot(root.path)
        case .compress:
            guard let destinationURL else {
                throw XPCStagingError.missingPath("destination")
            }
            let inputs = request.inputPaths.map(URL.init(fileURLWithPath:))
            let stagedInputs = try stageInputs(inputs)
            let outputDirectory = root.appendingPathComponent("output", isDirectory: true)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let stagedOutput = outputDirectory.appendingPathComponent(destinationURL.lastPathComponent)
            stagedDestinationURL = stagedOutput
            stagedArchiveURL = nil
            xpcRequest = request
                .replacingInputPaths(stagedInputs.map(\.path))
                .replacingDestinationPath(stagedOutput.path)
                .replacingStagingRoot(root.path)
        case .add:
            guard let archiveURL else {
                throw XPCStagingError.missingPath("archive")
            }
            let stagedArchive = try stageArchive(archiveURL)
            let stagedInputs = try stageInputs(request.inputPaths.map(URL.init(fileURLWithPath:)))
            stagedArchiveURL = stagedArchive
            stagedDestinationURL = nil
            xpcRequest = request
                .replacingArchivePath(stagedArchive.path)
                .replacingInputPaths(stagedInputs.map(\.path))
                .replacingStagingRoot(root.path)
        case .replace:
            guard let archiveURL else {
                throw XPCStagingError.missingPath("archive")
            }
            let stagedArchive = try stageArchive(archiveURL)
            let replacements = try stageReplacements(request.replacements)
            stagedArchiveURL = stagedArchive
            stagedDestinationURL = nil
            xpcRequest = request
                .replacingArchivePath(stagedArchive.path)
                .replacingReplacements(replacements)
                .replacingStagingRoot(root.path)
        case .delete:
            guard let archiveURL else {
                throw XPCStagingError.missingPath("archive")
            }
            let stagedArchive = try stageArchive(archiveURL)
            stagedArchiveURL = stagedArchive
            stagedDestinationURL = nil
            xpcRequest = request
                .replacingArchivePath(stagedArchive.path)
                .replacingStagingRoot(root.path)
        case .preview:
            guard let archiveURL, self.destinationURL != nil else {
                throw XPCStagingError.missingPath("archive or destination")
            }
            let stagedArchive = try stageArchive(archiveURL)
            let stagedDestination = root.appendingPathComponent("preview", isDirectory: true)
            try FileManager.default.createDirectory(at: stagedDestination, withIntermediateDirectories: true)
            stagedArchiveURL = stagedArchive
            stagedDestinationURL = stagedDestination
            xpcRequest = request
                .replacingArchivePath(stagedArchive.path)
                .replacingDestinationPath(stagedDestination.path)
                .replacingStagingRoot(root.path)
        case .repair:
            guard let archiveURL, let destinationURL else {
                throw XPCStagingError.missingPath("archive or destination")
            }
            let stagedArchive = try stageArchive(archiveURL)
            let outputDirectory = root.appendingPathComponent("repair", isDirectory: true)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let stagedOutput = outputDirectory.appendingPathComponent(destinationURL.lastPathComponent)
            stagedArchiveURL = stagedArchive
            stagedDestinationURL = stagedOutput
            xpcRequest = request
                .replacingArchivePath(stagedArchive.path)
                .replacingDestinationPath(stagedOutput.path)
                .replacingStagingRoot(root.path)
        }
    }

    func finalize(_ response: ArchiveXPCResponse) throws -> ArchiveXPCResponse {
        switch request.operation {
        case .ping, .list, .test:
            return response
        case .extract:
            guard let destinationURL, let stagedDestinationURL else { return response }
            try withSecurityScope([destinationURL]) {
                try mergeTree(from: stagedDestinationURL, to: destinationURL, policy: request.overwritePolicy)
            }
            return response
        case .compress:
            guard let destinationURL, let stagedDestinationURL else { return response }
            let outputParent = destinationURL.deletingLastPathComponent()
            let stagedParent = stagedDestinationURL.deletingLastPathComponent()
            let stagedBase = outputBaseName(for: stagedDestinationURL)
            let originalBase = destinationURL.lastPathComponent
            try withSecurityScope([outputParent]) {
                for source in try FileManager.default.contentsOfDirectory(
                    at: stagedParent,
                    includingPropertiesForKeys: nil
                ) where source.lastPathComponent == stagedBase ||
                    source.lastPathComponent.hasPrefix(stagedBase + ".") {
                    let suffix = String(source.lastPathComponent.dropFirst(stagedBase.count))
                    let target = outputParent.appendingPathComponent(originalBase + suffix)
                    if FileManager.default.fileExists(atPath: target.path) {
                        try FileManager.default.removeItem(at: target)
                    }
                    try FileManager.default.copyItem(at: source, to: target)
                }
            }
            var result = response
            if let outputPath = response.outputPath {
                let suffix = String(outputPath.dropFirst(stagedDestinationURL.path.count))
                result.outputPath = destinationURL.path + suffix
            }
            return result
        case .add, .replace, .delete:
            guard let archiveURL, let stagedArchiveURL else { return response }
            try withSecurityScope([archiveURL]) {
                try replaceStagedArchive(stagedArchiveURL, at: archiveURL)
            }
            return response
        case .preview:
            guard let destinationURL, let stagedDestinationURL else { return response }
            try withSecurityScope([destinationURL]) {
                try mergeTree(from: stagedDestinationURL, to: destinationURL, policy: .overwrite)
            }
            var result = response
            result.previewWorkingDirectory = destinationURL.path
            if let outputPath = response.outputPath {
                let relative = String(outputPath.dropFirst(stagedDestinationURL.path.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                result.outputPath = destinationURL.appendingPathComponent(relative).path
            }
            return result
        case .repair:
            guard let destinationURL, let stagedDestinationURL else { return response }
            try withSecurityScope([destinationURL.deletingLastPathComponent()]) {
                try replaceFile(stagedDestinationURL, at: destinationURL)
            }
            var result = response
            result.outputPath = destinationURL.path
            return result
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    private func stageArchive(_ source: URL) throws -> URL {
        let fileManager = FileManager.default
        let directory = root.appendingPathComponent("archive", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let staged = directory.appendingPathComponent(source.lastPathComponent)
        try copyScoped(source, to: staged)
        if source.pathExtension.lowercased() == "001" {
            let parent = source.deletingLastPathComponent()
            let prefix = source.lastPathComponent + "."
            if let contents = try? fileManager.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: nil
            ) {
                for sibling in contents
                    where sibling.lastPathComponent.hasPrefix(prefix) &&
                        sibling.lastPathComponent != source.lastPathComponent {
                    try copyScoped(
                        sibling,
                        to: directory.appendingPathComponent(sibling.lastPathComponent)
                    )
                }
            }
        }
        return staged
    }

    private func stageInputs(_ inputs: [URL]) throws -> [URL] {
        let fileManager = FileManager.default
        let inputsDirectory = root.appendingPathComponent("inputs", isDirectory: true)
        try fileManager.createDirectory(at: inputsDirectory, withIntermediateDirectories: true)
        let rootURL = commonParent(for: inputs)
        var staged: [URL] = []
        for input in inputs {
            let relative: String
            if let rootURL, input.standardizedFileURL.path.hasPrefix(rootURL.path) {
                relative = String(input.standardizedFileURL.path.dropFirst(rootURL.path.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            } else {
                relative = input.lastPathComponent
            }
            let target = inputsDirectory.appendingPathComponent(
                relative.isEmpty ? input.lastPathComponent : relative
            )
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try copyScoped(input, to: target)
            staged.append(target)
        }
        return staged
    }

    private func stageReplacements(_ replacements: [ArchiveXPCReplacement]) throws -> [ArchiveXPCReplacement] {
        var staged: [ArchiveXPCReplacement] = []
        for (index, replacement) in replacements.enumerated() {
            let source = URL(fileURLWithPath: replacement.sourcePath)
            let target = root.appendingPathComponent("replacements/\(index)/\(source.lastPathComponent)")
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try copyScoped(source, to: target)
            staged.append(
                ArchiveXPCReplacement(archivePath: replacement.archivePath, sourcePath: target.path)
            )
        }
        return staged
    }

    private func copyScoped(_ source: URL, to destination: URL) throws {
        try withSecurityScope([source]) {
            do {
                try FileManager.default.copyItem(at: source, to: destination)
            } catch {
                throw XPCStagingError.copyFailed(source.path, error.localizedDescription)
            }
        }
    }

    private func withSecurityScope<T>(_ urls: [URL], _ body: () throws -> T) rethrows -> T {
        var started: [URL] = []
        for url in urls {
            let root = nearestExistingAncestor(of: url)
            if root.startAccessingSecurityScopedResource() {
                started.append(root)
            }
        }
        defer {
            for url in started { url.stopAccessingSecurityScopedResource() }
        }
        return try body()
    }

    private func nearestExistingAncestor(of url: URL) -> URL {
        var candidate = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }

    private func commonParent(for urls: [URL]) -> URL? {
        guard let first = urls.first else { return nil }
        var components = first.standardizedFileURL.deletingLastPathComponent().pathComponents
        for url in urls.dropFirst() {
            let other = url.standardizedFileURL.deletingLastPathComponent().pathComponents
            var count = 0
            while count < components.count, count < other.count, components[count] == other[count] {
                count += 1
            }
            components = Array(components.prefix(count))
        }
        guard !components.isEmpty else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: components))
    }

    private func outputBaseName(for url: URL) -> String {
        let name = url.lastPathComponent
        if let range = name.range(of: #"\.\d{3,}$"#, options: .regularExpression) {
            return String(name[..<range.lowerBound])
        }
        return name
    }

    private func mergeTree(from source: URL, to destination: URL, policy: ArchiveOverwritePolicy) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for child in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            let target = destination.appendingPathComponent(child.lastPathComponent)
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try mergeTree(from: child, to: target, policy: policy)
                continue
            }
            if fileManager.fileExists(atPath: target.path) {
                switch policy {
                case .skip:
                    continue
                case .newerOnly:
                    let sourceDate = try? child.resourceValues(forKeys: [.contentModificationDateKey])
                    let targetDate = try? target.resourceValues(forKeys: [.contentModificationDateKey])
                    guard (sourceDate?.contentModificationDate ?? .distantPast) >
                            (targetDate?.contentModificationDate ?? .distantFuture) else {
                        continue
                    }
                    try fileManager.removeItem(at: target)
                case .overwrite, .ask:
                    try fileManager.removeItem(at: target)
                case .keepBoth:
                    var unique = target
                    var index = 2
                    while fileManager.fileExists(atPath: unique.path) {
                        unique = destination.appendingPathComponent(
                            "\(target.deletingPathExtension().lastPathComponent) \(index).\(target.pathExtension)"
                        )
                        index += 1
                    }
                    try fileManager.copyItem(at: child, to: unique)
                    continue
                }
            }
            try fileManager.copyItem(at: child, to: target)
        }
    }

    private func replaceStagedArchive(_ staged: URL, at original: URL) throws {
        if FileManager.default.fileExists(atPath: original.path) {
            let temporary = original.deletingLastPathComponent()
                .appendingPathComponent(".nanzip-replace-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try FileManager.default.copyItem(at: staged, to: temporary)
            _ = try FileManager.default.replaceItemAt(original, withItemAt: temporary)
        } else {
            try FileManager.default.copyItem(at: staged, to: original)
        }
    }

    private func replaceFile(_ staged: URL, at original: URL) throws {
        if FileManager.default.fileExists(atPath: original.path) {
            let temporary = original.deletingLastPathComponent()
                .appendingPathComponent(".nanzip-replace-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try FileManager.default.copyItem(at: staged, to: temporary)
            _ = try FileManager.default.replaceItemAt(original, withItemAt: temporary)
        } else {
            try FileManager.default.copyItem(at: staged, to: original)
        }
    }
}
