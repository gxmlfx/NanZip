import Foundation

public enum ExtractionDestinationPolicy: String, CaseIterable, Codable, Sendable {
    case smart
    case here
    case archiveNamedFolder
    case custom

    public var title: String {
        switch self {
        case .smart: return "智能解压"
        case .here: return "解压到当前目录"
        case .archiveNamedFolder: return "解压到归档同名文件夹"
        case .custom: return "解压到指定文件夹"
        }
    }
}

public enum ExtractionDestinationResolver {
    public static func archiveBaseName(for archiveURL: URL) -> String {
        var name = archiveURL.lastPathComponent
        let extensions = [
            ".tar.gz", ".tar.bz2", ".tar.xz", ".tgz", ".tbz2", ".tbz", ".txz"
        ]
        let lower = name.lowercased()
        for suffix in extensions where lower.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            return name.isEmpty ? "解压结果" : name
        }
        while !name.isEmpty {
            let ext = (name as NSString).pathExtension.lowercased()
            guard ArchiveService.supportedExtensions.contains(ext) else { break }
            name = (name as NSString).deletingPathExtension
        }
        return name.isEmpty ? "解压结果" : name
    }

    public static func resolve(
        archiveURL: URL,
        items: [ArchiveItem],
        policy: ExtractionDestinationPolicy,
        customDestination: URL?
    ) -> URL {
        let parent = archiveURL.deletingLastPathComponent()
        let named = parent.appendingPathComponent(
            archiveBaseName(for: archiveURL),
            isDirectory: true
        )

        switch policy {
        case .here:
            return parent
        case .archiveNamedFolder:
            return named
        case .custom:
            return customDestination ?? named
        case .smart:
            let roots = Set(items.compactMap { item -> String? in
                let component = item.path
                    .replacingOccurrences(of: "\\", with: "/")
                    .split(separator: "/", omittingEmptySubsequences: true)
                    .first
                return component.map(String.init)
            })
            let hasSingleDirectoryRoot = roots.count == 1 &&
                items.contains { $0.isDirectory && $0.path.split(separator: "/").count == 1 }
            return hasSingleDirectoryRoot ? parent : named
        }
    }
}
