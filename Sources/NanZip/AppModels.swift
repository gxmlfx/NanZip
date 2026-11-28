import Foundation
import NanZipCore

enum BatchOperationMode: String, CaseIterable, Identifiable {
    case extract = "批量解压"
    case compress = "批量压缩"

    var id: String { rawValue }
}

enum BatchItemState: Equatable {
    case waiting
    case running
    case success(String)
    case failed(String)

    var title: String {
        switch self {
        case .waiting: return "等待"
        case .running: return "处理中"
        case .success(let message): return message
        case .failed(let message): return message
        }
    }

    var symbol: String {
        switch self {
        case .waiting: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }
}

struct BatchQueueItem: Identifiable {
    let id = UUID()
    let url: URL
    var state: BatchItemState = .waiting
}

struct ArchiveBreadcrumb: Identifiable {
    let id = UUID()
    let archiveURL: URL
    let nestedEntryPath: String?
    let temporaryDirectory: URL?
}

enum CompressionVolumeChoice: Int64, CaseIterable, Identifiable {
    case none = 0
    case tenMB = 10_485_760
    case fiftyMB = 52_428_800
    case hundredMB = 104_857_600
    case fiveHundredMB = 524_288_000

    var id: Int64 { rawValue }

    var title: String {
        switch self {
        case .none: return "不分卷"
        case .tenMB: return "10 MB"
        case .fiftyMB: return "50 MB"
        case .hundredMB: return "100 MB"
        case .fiveHundredMB: return "500 MB"
        }
    }

    var bytes: Int64? { self == .none ? nil : rawValue }
}

enum NanZipQuickAction: String {
    case compress
    case extractHere
    case extractChoose
}

struct NanZipQuickActionPayload {
    let action: NanZipQuickAction
    let urls: [URL]
}

extension Notification.Name {
    static let nanZipQuickAction = Notification.Name("com.gxmlfx.nanzip.quick-action")
}
