// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import Foundation
import IOKit.ps
import WakeMacCore
import WakeMacPower

private final class SystemSleepSwitch: SleepSwitch {
    // A root-owned journal allows launchd's restarted helper to undo its own
    // setting after a crash. Never reset an unrelated pre-existing inhibitor.
    private let journal = URL(fileURLWithPath: "/var/db/local.orx.WakeMac.PowerLease")
    func powerSource() -> SleepPowerSource? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return nil }
        switch source {
        case kIOPSACPowerValue: return .external
        case kIOPSBatteryPowerValue: return .battery
        default: return nil
        }
    }
    func read() throws -> Bool {
        let text = try CommandRunner.run("/usr/bin/pmset", ["-g"], timeout: 5)
        guard let disabled = SystemParsing.sleepDisabled(text) else { throw ModeError("无法读取系统防休眠状态。") }
        return disabled
    }
    func setDisabled(_ enabled: Bool) throws {
        if enabled {
            try Data("WakeMac\n".utf8).write(to: journal, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journal.path)
        }
        _ = try CommandRunner.run("/usr/bin/pmset", ["-a", "disablesleep", enabled ? "1" : "0"], timeout: 5)
        guard try read() == enabled else { throw ModeError("系统电源状态与请求不一致。") }
        if !enabled && FileManager.default.fileExists(atPath: journal.path) { try FileManager.default.removeItem(at: journal) }
    }
    func recoverJournal() throws {
        if FileManager.default.fileExists(atPath: journal.path) { try setDisabled(false) }
    }
}

private final class ClientSession: NSObject, PowerServiceProtocol {
    let id = UUID()
    let host: HelperHost
    init(host: HelperHost) { self.host = host }
    func setBackground(_ enabled: Bool, reply: @escaping (String?) -> Void) {
        host.queue.async {
            do {
                if enabled { try self.host.lease.begin(owner: self.id, uptime: ProcessInfo.processInfo.systemUptime) }
                else { try self.host.lease.end(owner: self.id) }
                reply(nil)
            } catch { reply(error.localizedDescription) }
        }
    }
    func renew(reply: @escaping (String?) -> Void) {
        host.queue.async {
            do { try self.host.lease.renew(owner: self.id, uptime: ProcessInfo.processInfo.systemUptime); reply(nil) }
            catch { reply(error.localizedDescription) }
        }
    }
}

private final class HelperHost: NSObject, NSXPCListenerDelegate {
    let queue = DispatchQueue(label: "WakeMac.PowerLease")
    let lease: SleepLease
    let requirement: String
    var watchdog: DispatchSourceTimer?
    init(power: SystemSleepSwitch, requirement: String) {
        lease = SleepLease(power: power); self.requirement = requirement
        super.init()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in
            do { try self?.lease.expire(uptime: ProcessInfo.processInfo.systemUptime) }
            catch { fputs("WakeMac: sleep recovery failed; retrying.\n", stderr) }
        }
        timer.resume(); watchdog = timer
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0 else { return false }
        let session = ClientSession(host: self)
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: PowerServiceProtocol.self)
        connection.exportedObject = session
        connection.invalidationHandler = { [weak self] in
            self?.queue.async {
                do { try self?.lease.end(owner: session.id) }
                catch { fputs("WakeMac: disconnected-client recovery failed; watchdog will retry.\n", stderr) }
            }
        }
        connection.resume()
        return true
    }
}

@main struct HelperMain {
    static func main() {
        guard getuid() == 0 else { fputs("WakeMacPowerHelper must be launched by the approved system service.\n", stderr); exit(1) }
        do {
            let power = SystemSleepSwitch()
            try power.recoverJournal()
            let host = HelperHost(power: power, requirement: try PowerService.peerRequirement(identifier: PowerService.appIdentifier))
            let listener = NSXPCListener(machServiceName: PowerService.identifier)
            listener.delegate = host; listener.resume()
            withExtendedLifetime((host, listener)) { RunLoop.current.run() }
        } catch { fputs("WakeMac: helper startup or recovery failed.\n", stderr); exit(1) }
    }
}
