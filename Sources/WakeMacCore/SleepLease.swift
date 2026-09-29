import Foundation

public protocol SleepSwitch {
    func read() throws -> Bool
    func setDisabled(_ enabled: Bool) throws
}

/// A single client's temporary ownership of the global sleep switch.
/// All calls are serialized by the helper. Failed recovery retains ownership
/// so the watchdog can retry rather than silently abandon a disabled system.
public final class SleepLease {
    private let power: any SleepSwitch
    private var owner: UUID?
    private var expires: TimeInterval?
    public init(power: any SleepSwitch) { self.power = power }
    public func begin(owner client: UUID, uptime: TimeInterval) throws {
        if let owner {
            guard owner == client else { throw ModeError("另一个 WakeMac 实例正在使用合盖服务。") }
        } else {
            guard try !power.read() else { throw ModeError("系统防休眠已被其他程序开启，请先在原程序中恢复休眠。") }
        }
        owner = client; expires = uptime + 30
        try power.setDisabled(true)
        guard try power.read() else { throw ModeError("合盖防休眠未通过系统回读核验。") }
    }
    public func renew(owner client: UUID, uptime: TimeInterval) throws {
        guard owner == client, let expires, uptime < expires else { throw ModeError("合盖会话已失效，请重新选择工作模式。") }
        guard try power.read() else { throw ModeError("系统防休眠已被关闭，请重新选择工作模式。") }
        self.expires = uptime + 30
    }
    public func end(owner client: UUID) throws {
        guard owner == client else { return }
        try restore()
    }
    public func expire(uptime: TimeInterval) throws {
        if let expires, uptime >= expires { try restore() }
    }
    private func restore() throws {
        try power.setDisabled(false)
        guard try !power.read() else { throw ModeError("恢复休眠未通过系统回读核验。") }
        owner = nil; expires = nil
    }
}
