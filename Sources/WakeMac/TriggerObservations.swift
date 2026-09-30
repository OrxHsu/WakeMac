// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import AppKit
import CoreGraphics
import CoreAudio
import CoreWLAN
import CoreBluetooth
import CoreLocation
import IOBluetooth
import IOKit
import IOKit.ps
import SystemConfiguration
import Darwin

struct TriggerDevice: Equatable { var id: String; var name: String }
struct TriggerSuggestion: Identifiable, Equatable { var id: String; var title: String; var value: String }
struct TriggerSnapshot {
    var observedAt: Date?
    var connectedDisplay: Bool?
    var externalDisplay: Bool?
    var displayMirroring: Bool?
    var usbDevices: [TriggerDevice]?
    var bluetoothDevices: [TriggerDevice]?
    var runningApps: Set<String>?
    var runningAppChoices: [TriggerDevice]?
    var frontmostApp: String?
    var processes: [TriggerDevice]?
    var processListComplete: Bool?
    var batteryPercent: Int?
    var batteryCharging: Bool?
    var acConnected: Bool?
    var ipAddresses: Set<String>?
    var wifiSSID: String?
    var ciscoVPN: Bool?
    var dnsServers: Set<String>?
    var headphones: Bool?
    var audioOutput: TriggerDevice?
    var mountedVolumes: [TriggerDevice]?
    var cpuPercent: Double?
    var idleSeconds: Double?
    var unavailable: [TriggerKind: String] = [:]

    func suggestions(for kind: TriggerKind) -> [TriggerSuggestion] {
        let devices: [TriggerDevice]
        switch kind {
        case .usbDevice: devices = usbDevices ?? []
        case .bluetoothDevice: devices = bluetoothDevices ?? []
        case .audioOutput: devices = audioOutput.map { [$0] } ?? []
        case .mountedVolume: devices = mountedVolumes ?? []
        case .appRunning, .appFrontmost:
            devices = runningAppChoices ?? (runningApps ?? []).sorted().map { .init(id: $0, name: $0) }
        case .processRunning: devices = processes ?? []
        case .wifiSSID: devices = wifiSSID.map { [.init(id: $0, name: $0)] } ?? []
        case .ipAddress: devices = (ipAddresses ?? []).sorted().map { .init(id: $0, name: $0) }
        case .dnsServer: devices = (dnsServers ?? []).sorted().map { .init(id: $0, name: $0) }
        default: return []
        }
        return devices.map { device in
            // USB registry IDs change on reconnect. Prefer a unique device name;
            // duplicate names remain distinguishable by their current registry IDs.
            let value = kind == .usbDevice && devices.filter({ $0.name == device.name }).count == 1 ? device.name : device.id
            let duplicate = devices.filter { $0.name == device.name }.count > 1
            return .init(id: device.id, title: duplicate ? device.name + " · " + device.id : device.name, value: value)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func evaluate(_ condition: TriggerCondition, now: Date? = nil, calendar: Calendar = TriggerWeeklySchedule.localCalendar) -> TriggerConditionResult {
        if let error = condition.validationError { return .init(state: .unknown, detail: error) }
        let value = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let result: Bool?
        let detail: String
        switch condition.kind {
        case .externalDisplay:
            result = condition.ignoreBuiltInDisplay ? externalDisplay : connectedDisplay
            detail = condition.ignoreBuiltInDisplay ? (externalDisplay == true ? "已连接外接显示器" : "没有外接显示器") : (connectedDisplay == true ? "已连接显示器（包括内建）" : "没有已连接显示器")
        case .displayMirroring: result = displayMirroring; detail = displayMirroring == true ? "正在镜像" : "没有镜像"
        case .usbDevice: result = usbDevices.map { Self.contains($0, value) }; detail = Self.describe(usbDevices)
        case .bluetoothDevice: result = bluetoothDevices.map { Self.contains($0, value) }; detail = Self.describe(bluetoothDevices)
        case .appRunning: result = runningApps.map { $0.contains(value) }; detail = runningApps?.sorted().joined(separator: "、") ?? ""
        case .appFrontmost: result = frontmostApp.map { $0 == value }; detail = frontmostApp ?? ""
        case .processRunning:
            if let processes {
                if processes.contains(where: { Self.normalizedProcessPath($0.id) == Self.normalizedProcessPath(value) }) { result = true }
                else { result = processListComplete == true ? false : nil }
            } else { result = nil }
            detail = processes?.filter { Self.normalizedProcessPath($0.id) == Self.normalizedProcessPath(value) }.map(\.name).joined(separator: "、") ?? ""
        case .weeklySchedule:
            if let date = now ?? observedAt { result = condition.schedule?.matches(at: date, calendar: calendar) }
            else { result = nil }
            detail = (condition.schedule?.summary ?? "") + " · 当前当地时间"
        case .batteryCharging: result = batteryCharging; detail = batteryCharging == true ? "电池正在充电" : "电池未充电"
        case .batteryAbove: result = batteryPercent.flatMap { (0...100).contains($0) ? Double($0) > (Double(value) ?? .infinity) : nil }; detail = batteryPercent.map { "\($0)%" } ?? ""
        case .acConnected: result = acConnected; detail = acConnected == true ? "电源已连接" : "电源已断开"
        case .acDisconnected: result = acConnected.map { !$0 }; detail = acConnected == true ? "电源已连接" : "电源已断开"
        case .ipAddress: result = ipAddresses.map { addresses in addresses.contains { Self.equalIP($0, value) } }; detail = ipAddresses?.sorted().joined(separator: "、") ?? ""
        case .wifiSSID: result = wifiSSID.map { $0 == value }; detail = wifiSSID ?? ""
        case .ciscoVPN: result = ciscoVPN; detail = ciscoVPN == true ? "Cisco VPN 已连接" : "未发现已连接的 Cisco VPN"
        case .dnsServer: result = dnsServers.map { servers in servers.contains { Self.equalIP($0, value) } }; detail = dnsServers?.sorted().joined(separator: "、") ?? ""
        case .headphones: result = headphones; detail = audioOutput?.name ?? ""
        case .audioOutput: result = audioOutput.map { Self.contains([$0], value) }; detail = audioOutput.map { "\($0.name) [\($0.id)]" } ?? ""
        case .mountedVolume: result = mountedVolumes.map { Self.contains($0, value) }; detail = Self.describe(mountedVolumes)
        case .cpuAbove: result = cpuPercent.flatMap { $0.isFinite && (0...100).contains($0) ? $0 > (Double(value) ?? .infinity) : nil }; detail = cpuPercent.map { String(format: "%.1f%%", $0) } ?? ""
        case .idleAbove: result = idleSeconds.flatMap { $0.isFinite && $0 >= 0 ? $0 > (Double(value) ?? .infinity) : nil }; detail = idleSeconds.map { String(format: "%.0f 秒", $0) } ?? ""
        }
        guard let result else { return .init(state: .unknown, detail: unavailable[condition.kind] ?? "当前系统未提供此观测，条件不会匹配。") }
        return .init(state: result ? .matched : .unmatched, detail: detail.isEmpty ? "没有匹配的设备或应用" : detail)
    }
    static func normalizedProcessPath(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path }
    private static func contains(_ devices: [TriggerDevice], _ value: String) -> Bool {
        devices.contains { $0.id.caseInsensitiveCompare(value) == .orderedSame || $0.name.caseInsensitiveCompare(value) == .orderedSame }
    }
    private static func describe(_ devices: [TriggerDevice]?) -> String {
        devices?.map { "\($0.name) [\($0.id)]" }.joined(separator: "、") ?? ""
    }
    private static func equalIP(_ lhs: String, _ rhs: String) -> Bool {
        var a = in6_addr(), b = in6_addr(), x = in_addr(), y = in_addr()
        if lhs.withCString({ inet_pton(AF_INET6, $0, &a) }) == 1 && rhs.withCString({ inet_pton(AF_INET6, $0, &b) }) == 1 {
            return withUnsafeBytes(of: a) { aa in withUnsafeBytes(of: b) { bb in aa.elementsEqual(bb) } }
        }
        return lhs.withCString({ inet_pton(AF_INET, $0, &x) }) == 1 && rhs.withCString({ inet_pton(AF_INET, $0, &y) }) == 1 && x.s_addr == y.s_addr
    }
}

/// Cumulative CPU counters need two samples; a reset or zero delta is unavailable.
struct TriggerCPUSampler {
    struct Counters { var user: UInt64; var system: UInt64; var idle: UInt64; var nice: UInt64 }
    private var previous: Counters?
    mutating func sample(_ current: Counters) -> Double? {
        defer { previous = current }
        guard let old = previous, current.user >= old.user, current.system >= old.system,
              current.idle >= old.idle, current.nice >= old.nice else { return nil }
        let busy = Double(current.user - old.user) + Double(current.system - old.system) + Double(current.nice - old.nice)
        let total = busy + Double(current.idle - old.idle)
        return total > 0 ? busy / total * 100 : nil
    }
}

@MainActor protocol TriggerObservationSource {
    func read(kinds: Set<TriggerKind>, now: Date) async -> TriggerSnapshot
    func openPermissionSettings(for kind: TriggerKind)
    func requestPermission(for kind: TriggerKind)
}
extension TriggerObservationSource {
    func openPermissionSettings(for kind: TriggerKind) {}
    func requestPermission(for kind: TriggerKind) {}
}

@MainActor final class NativeTriggerObservations: NSObject, TriggerObservationSource, CLLocationManagerDelegate, CBCentralManagerDelegate {
    private var cpu = TriggerCPUSampler()
    private var locationManager: CLLocationManager?
    private var bluetoothManager: CBCentralManager?
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {}
    func openPermissionSettings(for kind: TriggerKind) {
        let pane = kind == .bluetoothDevice ? "Privacy_Bluetooth" : "Privacy_LocationServices"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
    func requestPermission(for kind: TriggerKind) {
        if kind == .bluetoothDevice {
            guard Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil || Bundle.main.object(forInfoDictionaryKey: "NSBluetoothUsageDescription") != nil else { openPermissionSettings(for: kind); return }
            bluetoothManager = CBCentralManager(delegate: self, queue: .main)
        } else if kind == .wifiSSID {
            guard Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil else { openPermissionSettings(for: kind); return }
            let manager = CLLocationManager(); manager.delegate = self; locationManager = manager
            manager.requestWhenInUseAuthorization()
        }
    }
    func read(kinds: Set<TriggerKind>, now: Date) async -> TriggerSnapshot {
        var s = TriggerSnapshot()
        s.observedAt = now
        if !kinds.isDisjoint(with: [.externalDisplay, .displayMirroring]) {
            var count: UInt32 = 0
            if CGGetOnlineDisplayList(0, nil, &count) == .success {
                var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
                if CGGetOnlineDisplayList(count, &displays, &count) == .success {
                    let ids = Array(displays.prefix(Int(count)))
                    s.connectedDisplay = !ids.isEmpty
                    s.externalDisplay = ids.contains { CGDisplayIsBuiltin($0) == 0 }
                    s.displayMirroring = ids.contains { CGDisplayIsInMirrorSet($0) != 0 }
                }
            }
        }
        if kinds.contains(.usbDevice) { s.usbDevices = readUSB() }
        if kinds.contains(.bluetoothDevice) {
            switch CBManager.authorization {
            case .allowedAlways:
                if IOBluetoothHostController.default() != nil,
                   let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
                    s.bluetoothDevices = devices.filter { $0.isConnected() }.map { .init(id: $0.addressString ?? "", name: $0.name ?? "蓝牙设备") }
                } else { s.unavailable[.bluetoothDevice] = "蓝牙控制器或设备列表不可用。" }
            default: s.unavailable[.bluetoothDevice] = "读取蓝牙需要蓝牙权限；请主动授权后刷新。"
            }
        }
        if !kinds.isDisjoint(with: [.appRunning, .appFrontmost]) {
            let apps = NSWorkspace.shared.runningApplications
            s.runningApps = Set(apps.compactMap(\.bundleIdentifier))
            var seen = Set<String>()
            s.runningAppChoices = apps.compactMap { app in
                guard let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return TriggerDevice(id: id, name: app.localizedName ?? id)
            }
            s.frontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
        if kinds.contains(.processRunning) {
            let discovered = ProcessDiscovery.snapshot()
            if discovered.isAvailable {
                var seen = Set<String>()
                s.processes = discovered.processes.compactMap { process in
                    let path = TriggerSnapshot.normalizedProcessPath(process.executablePath)
                    guard seen.insert(path).inserted else { return nil }
                    return TriggerDevice(id: path, name: process.name)
                }
                s.processListComplete = discovered.isComplete
                if !discovered.isComplete { s.unavailable[.processRunning] = "部分进程无法读取；未发现目标时无法确认进程已经退出。" }
            } else { s.unavailable[.processRunning] = "系统未提供当前用户的完整进程观测。" }
        }
        if !kinds.isDisjoint(with: [.batteryCharging, .batteryAbove, .acConnected, .acDisconnected]) { readPower(into: &s) }
        if kinds.contains(.ipAddress) { s.ipAddresses = readIPs() }
        if kinds.contains(.wifiSSID) {
            let authorization = CLLocationManager().authorizationStatus
            if authorization == .authorizedAlways || authorization == .authorized {
                s.wifiSSID = CWWiFiClient.shared().interface()?.ssid()
                if s.wifiSSID == nil { s.unavailable[.wifiSSID] = "Wi-Fi 未连接或 macOS 隐私保护未提供 SSID；条件不会匹配。" }
            } else { s.unavailable[.wifiSSID] = "Wi-Fi 名称需要定位权限；请主动授权后刷新。" }
        }
        if !kinds.isDisjoint(with: [.dnsServer, .ciscoVPN]) { readNetwork(into: &s, kinds: kinds) }
        if !kinds.isDisjoint(with: [.audioOutput, .headphones]) { readAudio(into: &s) }
        if kinds.contains(.mountedVolume) {
            s.mountedVolumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [])?.map { url in
                .init(id: url.path, name: (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? url.lastPathComponent)
            }
        }
        if kinds.contains(.cpuAbove) {
            var info = host_cpu_load_info(), count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
            let host = mach_host_self()
            defer { _ = mach_port_deallocate(mach_task_self_, host) }
            let result = withUnsafeMutablePointer(to: &info) { pointer in pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) } }
            if result == KERN_SUCCESS {
                s.cpuPercent = cpu.sample(.init(user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1), idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3)))
            }
            if s.cpuPercent == nil { s.unavailable[.cpuAbove] = "CPU 需要两次有效采样；请稍后刷新。" }
        }
        if kinds.contains(.idleAbove) {
            let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
            if seconds.isFinite, seconds >= 0 { s.idleSeconds = seconds }
        }
        return s
    }
    private func readUSB() -> [TriggerDevice]? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var devices: [TriggerDevice] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var identifier: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &identifier) == KERN_SUCCESS else { continue }
            let name = IORegistryEntryCreateCFProperty(service, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            devices.append(.init(id: String(identifier), name: name ?? "USB 设备"))
        }
        return devices
    }
    private func readPower(into s: inout TriggerSnapshot) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return }
        if let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? {
            if type == kIOPSACPowerValue { s.acConnected = true }
            else if type == kIOPSBatteryPowerValue { s.acConnected = false }
        }
        guard let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let raw = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any], raw[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            if let current = raw[kIOPSCurrentCapacityKey] as? Int, let max = raw[kIOPSMaxCapacityKey] as? Int, max > 0 { s.batteryPercent = Int(Double(current) / Double(max) * 100) }
            s.batteryCharging = raw[kIOPSIsChargingKey] as? Bool
        }
    }
    private func readIPs() -> Set<String>? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return nil }
        defer { freeifaddrs(first) }
        var addresses = Set<String>(), cursor = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard entry.pointee.ifa_flags & UInt32(IFF_UP) != 0, let addr = entry.pointee.ifa_addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_INET) || addr.pointee.sa_family == UInt8(AF_INET6) else { continue }
            var text = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &text, socklen_t(text.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.insert(String(cString: text).components(separatedBy: "%")[0])
            }
        }
        return addresses
    }
    private func readNetwork(into s: inout TriggerSnapshot, kinds: Set<TriggerKind>) {
        guard let store = SCDynamicStoreCreate(nil, "WakeMac Triggers" as CFString, nil, nil) else { return }
        if kinds.contains(.dnsServer) {
            if let dns = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any], let addresses = dns["ServerAddresses"] as? [String] { s.dnsServers = Set(addresses) }
            else { s.unavailable[.dnsServer] = "系统没有提供当前 DNS 配置。" }
        }
        if kinds.contains(.ciscoVPN) {
            guard let preferences = SCPreferencesCreate(nil, "WakeMac Triggers" as CFString, nil), let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] else { return }
            var found = false, unknown = false, recognized = false
            for service in services {
                let name = (SCNetworkServiceGetName(service) as String? ?? "").lowercased()
                guard name.contains("cisco") || name.contains("anyconnect") || name.contains("secure client") else { continue }
                recognized = true
                guard let id = SCNetworkServiceGetServiceID(service), let connection = SCNetworkConnectionCreateWithServiceID(nil, id, nil, nil) else { unknown = true; continue }
                switch SCNetworkConnectionGetStatus(connection) {
                case .connected: found = true
                case .invalid: unknown = true
                default: break
                }
            }
            // Cisco NetworkExtension clients can be invisible to SCNetworkConnection.
            // Never interpret an unobservable client as disconnected.
            if found { s.ciscoVPN = true }
            else if unknown || !recognized { s.unavailable[.ciscoVPN] = "系统 VPN 服务未公开 Cisco 连接状态；无法确认。" }
            else { s.ciscoVPN = false }
        }
    }
    private func readAudio(into s: inout TriggerSnapshot) {
        var device = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device) == noErr, device != kAudioObjectUnknown else { return }
        func string(_ selector: AudioObjectPropertySelector) -> String? {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            // These two CoreAudio properties return caller-owned CFStrings.
            // Use unmanaged storage so the C API does not overwrite an ARC reference.
            var value: Unmanaged<CFString>?, count = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let result = withUnsafeMutablePointer(to: &value) { pointer in
                AudioObjectGetPropertyData(device, &address, 0, nil, &count, UnsafeMutableRawPointer(pointer))
            }
            guard result == noErr, let value else { return nil }
            return value.takeRetainedValue() as String
        }
        if let uid = string(kAudioDevicePropertyDeviceUID), let name = string(kAudioObjectPropertyName) { s.audioOutput = .init(id: uid, name: name) }
        var source: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(device, &property, 0, nil, &size, &source) == noErr {
            // Apple built-in output data-source identifier 'hdpn'.
            s.headphones = source == 0x6864706e
        } else {
            // Bluetooth/USB audio lacks a standardized headphone flag; selecting the
            // exact audio device is the supported way to identify these headphones.
            s.unavailable[.headphones] = "此音频设备未公开耳机标识；可使用“指定音频输出”选择设备。"
        }
    }
}
