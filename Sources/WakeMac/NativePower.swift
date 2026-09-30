import Foundation
import IOKit.pwr_mgt
import ServiceManagement
import WakeMacCore
import WakeMacPower

final class NativeSleepAssertion {
    private var id: IOPMAssertionID?
    var active: Bool? {
        guard let id else { return false }
        guard let properties = IOPMAssertionCopyProperties(id)?.takeRetainedValue() as? [String: Any],
              let level = properties[kIOPMAssertionLevelKey] as? NSNumber,
              properties[kIOPMAssertionTypeKey] as? String == kIOPMAssertionTypePreventUserIdleSystemSleep else { return nil }
        return level.uint32Value == UInt32(kIOPMAssertionLevelOn)
    }
    func acquire() throws {
        if active == true { return }
        try release()
        var created: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                               IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "WakeMac work session" as CFString, &created)
        guard result == kIOReturnSuccess else { throw ModeError("无法建立原生保活会话（\(result)）。") }
        id = created
        guard active == true else { throw ModeError("原生保活会话未通过系统回读核验。") }
    }
    func release() throws {
        guard let id else { return }
        let result = IOPMAssertionRelease(id)
        guard result == kIOReturnSuccess else { throw ModeError("无法释放原生保活会话（\(result)）。") }
        self.id = nil
    }
    deinit { if let id { IOPMAssertionRelease(id) } }
}

private final class ReplyGate {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
    func finish(_ result: Result<Void, Error>) {
        lock.lock(); let saved = continuation; continuation = nil; lock.unlock()
        saved?.resume(with: result)
    }
}

/// Used only from MacBackend's actor. A connection owns one helper lease;
/// invalidating it causes the helper to restore sleep.
protocol BackgroundLeaseClient: AnyObject {
    func setBackground(_ enabled: Bool) async throws
    func renew() async throws
}
final class PowerHelperClient: BackgroundLeaseClient {
    private var connection: NSXPCConnection?
    func setBackground(_ enabled: Bool) async throws {
        try await request { service, reply in service.setBackground(enabled, reply: reply) }
    }
    func renew() async throws {
        try await request { service, reply in service.renew(reply: reply) }
    }
    private func request(_ call: (PowerServiceProtocol, @escaping (String?) -> Void) -> Void) async throws {
        guard SMAppService.daemon(plistName: PowerService.plistName).status == .enabled else {
            throw ModeError("请在偏好设置中启用 WakeMac 合盖服务，并在系统设置中批准。桌面工作无需这项授权。")
        }
        let peerRequirement = try PowerService.peerRequirement(identifier: PowerService.identifier)
        let connection: NSXPCConnection
        if let current = self.connection { connection = current }
        else {
            connection = NSXPCConnection(machServiceName: PowerService.identifier, options: .privileged)
            connection.setCodeSigningRequirement(peerRequirement)
            connection.remoteObjectInterface = NSXPCInterface(with: PowerServiceProtocol.self)
            connection.resume(); self.connection = connection
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let gate = ReplyGate(continuation)
                let timeout = DispatchWorkItem {
                    gate.finish(.failure(ModeError("合盖服务响应超时；已断开连接以恢复休眠。")))
                    connection.invalidate()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: timeout)
                guard let service = connection.remoteObjectProxyWithErrorHandler({ error in
                    timeout.cancel(); gate.finish(.failure(error))
                }) as? PowerServiceProtocol else {
                    timeout.cancel(); gate.finish(.failure(ModeError("无法连接合盖服务。"))); return
                }
                call(service) { error in
                    timeout.cancel()
                    gate.finish(error.map { .failure(ModeError($0)) } ?? .success(()))
                }
            }
        } catch {
            connection.invalidate(); self.connection = nil
            throw error
        }
    }
    deinit { connection?.invalidate() }
}
