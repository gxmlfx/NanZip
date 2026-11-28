import Foundation
import NanZipCore

enum ArchiveXPCClientError: LocalizedError {
    case unavailable
    case invalidResponse
    case remote(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "独立 XPC 归档服务不可用。"
        case .invalidResponse:
            return "XPC 归档服务返回了无效响应。"
        case .remote(let message):
            return message
        case .timedOut:
            return "XPC 归档服务响应超时。"
        }
    }
}

final class ArchiveXPCClient: @unchecked Sendable {
    static let shared = ArchiveXPCClient()
    static let serviceName = "com.gxmlfx.nanzip.xpc"

    private let stateLock = NSLock()
    private var cachedAvailability: Bool?

    private init() {}

    var isLikelyAvailable: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cachedAvailability ?? true
    }

    func perform(_ request: ArchiveXPCRequest, timeout: TimeInterval = 60 * 60 * 24) throws -> ArchiveXPCResponse {
        let payload: Data
        do {
            payload = try JSONEncoder().encode(request)
        } catch {
            throw ArchiveXPCClientError.invalidResponse
        }

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: Result<Data, Error>?
        let connection = NSXPCConnection(serviceName: Self.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: NanZipXPCProtocol.self)
        connection.invalidationHandler = {
            lock.lock()
            let hasResult = result != nil
            lock.unlock()
            if !hasResult {
                lock.lock()
                result = .failure(ArchiveXPCClientError.unavailable)
                lock.unlock()
                semaphore.signal()
            }
        }
        connection.interruptionHandler = {
            lock.lock()
            let hasResult = result != nil
            lock.unlock()
            if !hasResult {
                lock.lock()
                result = .failure(ArchiveXPCClientError.unavailable)
                lock.unlock()
                semaphore.signal()
            }
        }
        connection.resume()
        defer { connection.invalidate() }

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            lock.lock()
            if result == nil {
                result = .failure(error)
                semaphore.signal()
            }
            lock.unlock()
        }) as? NanZipXPCProtocol else {
            throw ArchiveXPCClientError.unavailable
        }

        proxy.perform(payload) { data in
            lock.lock()
            if result == nil {
                result = .success(data)
                semaphore.signal()
            }
            lock.unlock()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw ArchiveXPCClientError.timedOut
        }

        lock.lock()
        let finalResult = result
        lock.unlock()
        guard let finalResult else {
            throw ArchiveXPCClientError.invalidResponse
        }

        let data: Data
        do {
            data = try finalResult.get()
        } catch {
            markUnavailableIfNeeded(error)
            throw ArchiveXPCClientError.unavailable
        }

        if let failure = try? JSONDecoder().decode(ArchiveXPCFailure.self, from: data) {
            throw ArchiveXPCClientError.remote(failure.message)
        }
        do {
            let response = try JSONDecoder().decode(ArchiveXPCResponse.self, from: data)
            stateLock.lock()
            cachedAvailability = true
            stateLock.unlock()
            return response
        } catch {
            throw ArchiveXPCClientError.invalidResponse
        }
    }

    func cancel(_ operationID: String) {
        let connection = NSXPCConnection(serviceName: Self.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: NanZipXPCProtocol.self)
        connection.resume()
        defer { connection.invalidate() }
        (connection.remoteObjectProxy as? NanZipXPCProtocol)?.cancel(operationID)
    }

    func ping() -> Bool {
        do {
            _ = try perform(ArchiveXPCRequest(operation: .ping), timeout: 3)
            return true
        } catch {
            return false
        }
    }

    private func markUnavailableIfNeeded(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain || nsError.domain == "NSXPCConnectionErrorDomain" {
            stateLock.lock()
            cachedAvailability = false
            stateLock.unlock()
        }
    }
}
