import Foundation
import Darwin

/// PID alone is not an identity: the kernel may reuse it immediately after exit.
struct NativeProcessIdentity: Hashable, Sendable {
    let pid: Int32
    let startedSeconds: UInt64
    let startedMicroseconds: UInt64
}
struct DiscoveredProcess: Identifiable, Hashable, Sendable {
    let identity: NativeProcessIdentity
    let name: String
    let executablePath: String
    var id: NativeProcessIdentity { identity }
}
enum NativeProcessReading: Equatable { case running, exited, unavailable }
struct ProcessDiscoverySnapshot: Sendable {
    let processes: [DiscoveredProcess]
    let unavailableCount: Int
    let isAvailable: Bool
    var isComplete: Bool { isAvailable && unavailableCount == 0 }
}

/// Read-only libproc metadata. Never reads argv/environment or launches a command.
enum ProcessDiscovery {
    static func snapshot() -> ProcessDiscoverySnapshot {
        let uid = getuid()
        let estimated = proc_listpids(UInt32(PROC_UID_ONLY), uid, nil, 0)
        guard estimated > 0 else { return .init(processes: [], unavailableCount: 0, isAvailable: false) }
        var capacity = Int(estimated) / MemoryLayout<pid_t>.stride + 64
        for _ in 0..<3 {
            guard capacity <= 65536 else { break }
            var pids = [pid_t](repeating: 0, count: capacity)
            let size = pids.count * MemoryLayout<pid_t>.stride
            let bytes = pids.withUnsafeMutableBytes { proc_listpids(UInt32(PROC_UID_ONLY), uid, $0.baseAddress, Int32(size)) }
            guard bytes > 0 else { return .init(processes: [], unavailableCount: 0, isAvailable: false) }
            if bytes >= size { capacity *= 2; continue }
            let count = min(pids.count, Int(bytes) / MemoryLayout<pid_t>.stride)
            var found: [DiscoveredProcess] = [], unknown = 0
            for pid in Set(pids.prefix(count)) where pid > 0 {
                switch read(pid: pid) {
                case .found(let process): found.append(process)
                case .gone: break
                case .unavailable: unknown += 1
                }
            }
            found.sort {
                let comparison = $0.name.localizedStandardCompare($1.name)
                return comparison == .orderedSame ? $0.identity.pid < $1.identity.pid : comparison == .orderedAscending
            }
            return .init(processes: found, unavailableCount: unknown, isAvailable: true)
        }
        // A truncated inventory cannot establish that a process is absent.
        return .init(processes: [], unavailableCount: 0, isAvailable: false)
    }

    static func process(pid: Int32) -> DiscoveredProcess? {
        if case .found(let process) = read(pid: pid) { return process }
        return nil
    }
    static func presence(of identity: NativeProcessIdentity) -> NativeProcessReading {
        switch bsd(pid: identity.pid) {
        case .found(let info):
            guard matches(identity, info), info.pbi_status != UInt32(SZOMB) else { return .exited }
            guard info.pbi_uid == getuid() else { return .unavailable }
            return .running
        case .gone: return .exited
        case .unavailable: return .unavailable
        }
    }
    private enum BSDReading { case found(proc_bsdinfo), gone, unavailable }
    private enum ProcessReading { case found(DiscoveredProcess), gone, unavailable }
    private static func bsd(pid: Int32) -> BSDReading {
        guard pid > 0 else { return .gone }
        var info = proc_bsdinfo()
        errno = 0
        let size = MemoryLayout<proc_bsdinfo>.size
        let bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        guard bytes == size else { return errno == ESRCH || errno == ENOENT ? .gone : .unavailable }
        return .found(info)
    }
    private static func read(pid: Int32) -> ProcessReading {
        let initial: proc_bsdinfo
        switch bsd(pid: pid) {
        case .found(let info): initial = info
        case .gone: return .gone
        case .unavailable: return .unavailable
        }
        guard initial.pbi_uid == getuid(), initial.pbi_status != UInt32(SZOMB) else { return .gone }
        let identity = NativeProcessIdentity(pid: pid, startedSeconds: initial.pbi_start_tvsec, startedMicroseconds: initial.pbi_start_tvusec)
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        errno = 0
        let bytes = path.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard bytes > 0 else { return errno == ESRCH || errno == ENOENT ? .gone : .unavailable }
        let executable = path.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        guard !executable.isEmpty else { return .unavailable }
        // Recheck after fetching the path so a reused PID cannot combine two processes' metadata.
        switch bsd(pid: pid) {
        case .found(let current):
            guard current.pbi_uid == getuid(), current.pbi_status != UInt32(SZOMB), matches(identity, current) else { return .gone }
        case .gone: return .gone
        case .unavailable: return .unavailable
        }
        var nameTuple = initial.pbi_name
        var commandTuple = initial.pbi_comm
        let name = withUnsafeBytes(of: &nameTuple) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let command = withUnsafeBytes(of: &commandTuple) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return .found(.init(identity: identity, name: name.isEmpty ? (command.isEmpty ? URL(fileURLWithPath: executable).lastPathComponent : command) : name,
                            executablePath: URL(fileURLWithPath: executable).standardizedFileURL.resolvingSymlinksInPath().path))
    }
    private static func matches(_ identity: NativeProcessIdentity, _ info: proc_bsdinfo) -> Bool {
        info.pbi_pid == UInt32(identity.pid) && info.pbi_start_tvsec == identity.startedSeconds && info.pbi_start_tvusec == identity.startedMicroseconds
    }
}
