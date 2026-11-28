import Foundation
import NanZipCore

final class StagingArea {
    let root: URL

    init() throws {
        try XPCSharedStorage.prepare()
        root = XPCSharedStorage.stagingRoot
            .appendingPathComponent("work", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func stageArchive(_ archiveURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let archiveDirectory = root.appendingPathComponent("archive", isDirectory: true)
        try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        let staged = archiveDirectory.appendingPathComponent(archiveURL.lastPathComponent)
        do {
            try fileManager.copyItem(at: archiveURL, to: staged)
        } catch {
            throw XPCSecurityError.inaccessibleGrant("copy \(archiveURL.path) -> \(staged.path): \(error.localizedDescription)")
        }

        // A split archive needs its sibling volumes beside the first part.
        if archiveURL.pathExtension.lowercased() == "001" {
            let parent = archiveURL.deletingLastPathComponent()
            let prefix = archiveURL.lastPathComponent + "."
            if let contents = try? fileManager.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: nil
            ) {
                for sibling in contents
                    where sibling.lastPathComponent.hasPrefix(prefix) &&
                        sibling.lastPathComponent != archiveURL.lastPathComponent {
                    let target = archiveDirectory.appendingPathComponent(sibling.lastPathComponent)
                    try fileManager.copyItem(at: sibling, to: target)
                }
            }
        }
        return staged
    }

    func stageInputs(_ inputURLs: [URL], relativeTo rootURL: URL?) throws -> [URL] {
        let fileManager = FileManager.default
        let inputsRoot = root.appendingPathComponent("inputs", isDirectory: true)
        try fileManager.createDirectory(at: inputsRoot, withIntermediateDirectories: true)
        var staged: [URL] = []
        for input in inputURLs {
            let relative: String
            if let rootURL, input.path.hasPrefix(rootURL.path) {
                relative = String(input.path.dropFirst(rootURL.path.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            } else {
                relative = input.lastPathComponent
            }
            let target = inputsRoot.appendingPathComponent(relative)
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: input, to: target)
            staged.append(target)
        }
        return staged
    }
}
