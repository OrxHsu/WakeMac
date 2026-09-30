import AppKit
import Combine
import WakeMacCore

/// Session plans are configuration only. Active sessions are deliberately never persisted.
enum SessionEndCondition: String, CaseIterable, Identifiable {
    case indefinite, duration, untilDate, application, process, download
    var id: String { rawValue }
    var title: String {
        switch self {
        case .indefinite: return "手动结束"
        case .duration: return "持续一段时间"
        case .untilDate: return "到指定时间"
        case .application: return "直到应用退出"
        case .process: return "直到进程结束"
        case .download: return "直到文件下载完成"
        }
    }
}

enum SessionApplicationReading: Equatable { case running([Int32]), absent, unavailable }
struct SessionFileStamp: Equatable {
    let bytes: Int64
    let modified: Date
    let identity: UInt64
}
enum SessionDownloadReading: Equatable { case file(SessionFileStamp), missing, unavailable }

struct SessionBehaviorOverride: Equatable {
    var display: Bool? = nil
    var saver: Bool? = nil
}

@MainActor final class SessionController: ObservableObject {
    @Published var endCondition: SessionEndCondition = .indefinite { didSet { preferences.set(endCondition.rawValue, forKey: "session.endCondition") } }
    @Published var durationMinutes: Double = 60 { didSet { if durationMinutes.isFinite, (1...10080).contains(durationMinutes) { preferences.set(durationMinutes, forKey: "session.durationMinutes") } } }
    @Published var endDate = Date().addingTimeInterval(3600) { didSet { if endDate.timeIntervalSince1970.isFinite { preferences.set(endDate, forKey: "session.endDate") } } }
    @Published var applicationURL: URL? { didSet { preferences.set(applicationURL?.path, forKey: "session.applicationPath") } }
    @Published var downloadURL: URL? { didSet { preferences.set(downloadURL?.path, forKey: "session.downloadPath") } }
    @Published var selectedProcess: DiscoveredProcess?
    @Published private(set) var processChoices: [DiscoveredProcess] = []
    @Published private(set) var processDiscoveryStatus = "点击刷新，读取当前用户的进程"
    @Published var effectOverrides: SessionBehaviorOverride?
    @Published var screenSaverExceptionBundleIDs: [String] = [] { didSet { preferences.set(screenSaverExceptionBundleIDs, forKey: "session.screenSaverExceptions") } }
    @Published var downloadStabilitySeconds: Double = 30 { didSet {
        let bounded = Self.validInterval(downloadStabilitySeconds, fallback: 30)
        if bounded != downloadStabilitySeconds { downloadStabilitySeconds = bounded; return }
        preferences.set(downloadStabilitySeconds, forKey: "session.downloadStabilitySeconds")
    } }
    @Published var mouseMovementIntervalSeconds: Double = 60 { didSet {
        let bounded = Self.validInterval(mouseMovementIntervalSeconds, fallback: 60)
        if bounded != mouseMovementIntervalSeconds { mouseMovementIntervalSeconds = bounded; return }
        preferences.set(mouseMovementIntervalSeconds, forKey: "session.mouseMovementIntervalSeconds")
    } }
    @Published var mouseIdleThresholdSeconds: Double = 60 { didSet {
        let bounded = Self.validInterval(mouseIdleThresholdSeconds, fallback: 60)
        if bounded != mouseIdleThresholdSeconds { mouseIdleThresholdSeconds = bounded; return }
        preferences.set(mouseIdleThresholdSeconds, forKey: "session.mouseIdleThresholdSeconds")
    } }
    @Published var mouseStopAfterIdleSeconds: Double? { didSet {
        let bounded = mouseStopAfterIdleSeconds.flatMap { $0.isFinite ? Self.validInterval($0, fallback: 3600) : nil }
        if bounded != mouseStopAfterIdleSeconds { mouseStopAfterIdleSeconds = bounded; return }
        preferences.set(mouseStopAfterIdleSeconds, forKey: "session.mouseStopAfterIdleSeconds")
    } }
    @Published var mouseOnlyWhenIdle = true { didSet { preferences.set(mouseOnlyWhenIdle, forKey: "session.mouseOnlyWhenIdle") } }
    @Published var diskAccessIntervalSeconds: Double = 60 { didSet {
        let bounded = Self.validInterval(diskAccessIntervalSeconds, fallback: 60)
        if bounded != diskAccessIntervalSeconds { diskAccessIntervalSeconds = bounded; return }
        preferences.set(diskAccessIntervalSeconds, forKey: "session.diskAccessIntervalSeconds")
    } }
    @Published var defaultMode: WorkMode = .desk { didSet { preferences.set(defaultMode == .background ? "background" : "desk", forKey: "session.defaultMode") } }
    @Published var preventDisplaySleep = false { didSet { saveChoices() } }
    @Published var preventScreenSaver = false { didSet { saveChoices() } }
    // Cursor motion always starts disabled. Granting Accessibility is a separate explicit action.
    @Published var moveCursor = false
    @Published var driveAlive = false { didSet { saveChoices() } }
    @Published var driveDirectories: [URL] = [] { didSet { preferences.set(driveDirectories.map(\.path), forKey: "session.driveDirectories") } }
    @Published private(set) var isActive = false
    @Published private(set) var isStarting = false
    @Published private(set) var status = "会话尚未开始"
    @Published private(set) var effectReport = SessionEffectReport()
    @Published private(set) var deadline: Date?
    @Published private(set) var downloadProgressPercent: Double?

    var onBegin: ((WorkMode) async -> Bool)?
    var onEnd: (() async -> Void)?
    var onExtended: ((Double) -> Void)?
    var workingProvider: (() -> Bool)?
    var applicationProbe: (URL) -> SessionApplicationReading = SessionController.readApplication
    var screenSaverExceptionProbe: (String) -> SessionApplicationReading = SessionController.readRunningBundleIdentifier
    var processProbe: (NativeProcessIdentity) -> NativeProcessReading = ProcessDiscovery.presence
    var processDiscovery: () -> ProcessDiscoverySnapshot = ProcessDiscovery.snapshot
    var downloadProbe: (URL) -> SessionDownloadReading = SessionController.readDownload
    private let preferences: UserDefaults
    private let effects: SessionEffectManaging
    private let downloadProgressObserver = SessionDownloadProgressObserver()
    private var generation = UUID()
    private var stopped = false
    private var plan: SessionPlan?
    private var downloadStamp: SessionFileStamp?
    private var downloadObservedProgress = false
    private var downloadStableSince: Date?
    private var downloadObservedURL: URL?
    private var downloadFinalBaseline: SessionDownloadReading?

    private enum SessionPlan { case indefinite, deadline(Date), application(URL), process(DiscoveredProcess), download(URL) }
    init(preferences: UserDefaults, effects: SessionEffectManaging? = nil) {
        self.preferences = preferences
        self.effects = effects ?? NativeSessionEffects()
        endCondition = preferences.string(forKey: "session.endCondition").flatMap(SessionEndCondition.init(rawValue:)) ?? .indefinite
        let duration = preferences.object(forKey: "session.durationMinutes") as? Double ?? 60
        durationMinutes = duration.isFinite && (1...10080).contains(duration) ? duration : 60
        endDate = preferences.object(forKey: "session.endDate") as? Date ?? Date().addingTimeInterval(3600)
        applicationURL = preferences.string(forKey: "session.applicationPath").map { URL(fileURLWithPath: $0) }
        downloadURL = preferences.string(forKey: "session.downloadPath").map { URL(fileURLWithPath: $0) }
        screenSaverExceptionBundleIDs = Array(Set(preferences.stringArray(forKey: "session.screenSaverExceptions") ?? [])).filter { !$0.isEmpty }.sorted()
        defaultMode = preferences.string(forKey: "session.defaultMode") == "background" ? .background : .desk
        preventDisplaySleep = preferences.bool(forKey: "session.preventDisplaySleep")
        preventScreenSaver = preferences.bool(forKey: "session.preventScreenSaver")
        driveAlive = preferences.bool(forKey: "session.driveAlive")
        downloadStabilitySeconds = Self.validInterval(preferences.object(forKey: "session.downloadStabilitySeconds") as? Double ?? 30, fallback: 30)
        mouseMovementIntervalSeconds = Self.validInterval(preferences.object(forKey: "session.mouseMovementIntervalSeconds") as? Double ?? 60, fallback: 60)
        diskAccessIntervalSeconds = Self.validInterval(preferences.object(forKey: "session.diskAccessIntervalSeconds") as? Double ?? 60, fallback: 60)
        mouseOnlyWhenIdle = preferences.object(forKey: "session.mouseOnlyWhenIdle") as? Bool ?? true
        mouseIdleThresholdSeconds = Self.validInterval(preferences.object(forKey: "session.mouseIdleThresholdSeconds") as? Double ?? 60, fallback: 60)
        if let stored = preferences.object(forKey: "session.mouseStopAfterIdleSeconds") as? Double, stored.isFinite { mouseStopAfterIdleSeconds = Self.validInterval(stored, fallback: 3600) }
        driveDirectories = (preferences.stringArray(forKey: "session.driveDirectories") ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var choices: SessionEffectChoices {
        SessionEffectChoices(preventDisplaySleep: effectivePreventDisplaySleep, preventScreenSaver: effectivePreventScreenSaver, moveCursor: moveCursor, driveAlive: driveAlive, mouseMovementIntervalSeconds: mouseMovementIntervalSeconds, mouseOnlyWhenIdle: mouseOnlyWhenIdle, mouseIdleThresholdSeconds: mouseIdleThresholdSeconds, mouseStopAfterIdleSeconds: mouseStopAfterIdleSeconds, diskAccessIntervalSeconds: diskAccessIntervalSeconds)
    }
    var effectivePreventDisplaySleep: Bool { effectOverrides?.display ?? preventDisplaySleep }
    var effectivePreventScreenSaver: Bool { effectOverrides?.saver ?? preventScreenSaver }
    var screenSaverExceptionActive: Bool {
        guard workingProvider?() == true else { return false }
        for identifier in screenSaverExceptionBundleIDs {
            switch screenSaverExceptionProbe(identifier) {
            case .running(let pids) where !pids.isEmpty: return true
            case .unavailable: return true // Unknown activity must not start a saver over an exception app.
            default: break
            }
        }
        return false
    }
    func setDisplayPrevention(_ enabled: Bool) {
        var value = effectOverrides ?? SessionBehaviorOverride(); value.display = enabled; effectOverrides = value
    }
    func setScreenSaverPrevention(_ enabled: Bool) {
        var value = effectOverrides ?? SessionBehaviorOverride(); value.saver = enabled; effectOverrides = value
    }
    private static func validInterval(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? min(max(value, 1), 86400) : fallback
    }
    func refreshProcesses() {
        let reading = processDiscovery()
        processChoices = reading.processes
        processDiscoveryStatus = !reading.isAvailable ? "无法读取进程列表，请重试" : reading.isComplete ? "已读取当前用户的 \(reading.processes.count) 个进程" : "已读取 \(reading.processes.count) 个进程；\(reading.unavailableCount) 个暂不可核验"
    }
    @discardableResult func extend(minutes: Double, now: Date = Date()) -> Bool {
        guard minutes.isFinite, (1...10080).contains(minutes) else { status = "延长时长须为 1 分钟至 7 天"; return false }
        guard !stopped, isActive, case .deadline(let current) = plan, current > now, workingProvider?() == true else {
            status = "只有已核验且尚未到期的定时会话可以延长"; return false
        }
        let next = current.addingTimeInterval(minutes * 60)
        guard next.timeIntervalSince1970.isFinite else { status = "延长后的时间无效"; return false }
        plan = .deadline(next); deadline = next; endDate = next
        status = sessionStatus(now: now)
        onExtended?(minutes)
        return true
    }
    private func saveChoices() {
        preferences.set(preventDisplaySleep, forKey: "session.preventDisplaySleep")
        preferences.set(preventScreenSaver, forKey: "session.preventScreenSaver")
        preferences.set(driveAlive, forKey: "session.driveAlive")
    }

    func start(now: Date = Date()) async {
        guard !stopped, !isActive, !isStarting else { return }
        effects.release(); effectReport = SessionEffectReport()
        downloadProgressObserver.stop(); downloadProgressPercent = nil
        downloadStamp = nil; downloadObservedProgress = false; downloadStableSince = nil; downloadObservedURL = nil; downloadFinalBaseline = nil
        let newPlan: SessionPlan
        switch endCondition {
        case .indefinite: newPlan = .indefinite
        case .duration:
            guard durationMinutes.isFinite, durationMinutes >= 1, durationMinutes <= 10080 else { status = "请选择 1 分钟至 7 天的时长"; return }
            newPlan = .deadline(now.addingTimeInterval(durationMinutes * 60))
        case .untilDate:
            guard endDate > now else { status = "结束时间必须晚于当前时间"; return }
            newPlan = .deadline(endDate)
        case .application:
            guard let url = applicationURL else { status = "请先选择正在运行的应用"; return }
            guard case .running(let pids) = applicationProbe(url), !pids.isEmpty else { status = "所选应用没有运行，或无法核验应用身份"; return }
            newPlan = .application(url)
        case .process:
            guard let process = selectedProcess, processProbe(process.identity) == .running else { status = "请先选择仍在运行且身份可核验的进程"; return }
            newPlan = .process(process)
        case .download:
            guard let selected = downloadURL else { status = "请先选择正在下载的文件"; return }
            let url = Self.downloadContainer(selected)
            switch downloadProbe(url) {
            case .file(let stamp): downloadStamp = stamp; downloadObservedURL = url
            case .missing: break
            case .unavailable: status = "无法读取所选文件，请重新选择"; return
            }
            if Self.isPartial(url) { downloadFinalBaseline = downloadProbe(url.deletingPathExtension()) }
            newPlan = .download(url)
        }
        guard let onBegin else { status = "会话控制暂不可用"; return }
        let token = UUID(); generation = token; isStarting = true; status = "正在核验工作模式…"
        let began = await onBegin(defaultMode == .background ? .background : .desk)
        guard generation == token, !stopped else { return }
        isStarting = false
        guard began, workingProvider?() == true else {
            effects.release(); status = "工作模式未通过核验，会话没有开始"; return
        }
        plan = newPlan; isActive = true
        if case .deadline(let value) = newPlan { deadline = value }
        else { deadline = nil }
        status = sessionStatus(now: now)
        if case .download(let url) = newPlan {
            let urls = Self.isPartial(url) ? [url, url.deletingPathExtension()] : [url]
            downloadProgressObserver.start(urls: urls) { [weak self] value in
                guard let self, self.generation == token, self.isActive else { return }
                self.downloadProgressPercent = value
            }
        }
        // Re-read immediately: the selected app may have exited while mode activation awaited.
        await tick(now: now)
    }

    func end() async {
        guard isActive || isStarting else { return }
        let wasActive = isActive
        clear(status: "会话已结束")
        if wasActive { await onEnd?() }
    }

    /// Called before every manual mode/lock action, so a monitored session cannot later undo it.
    func manualModeChanged() {
        if isActive || isStarting { clear(status: "会话已随手动操作取消") }
        else { effects.release(); effectReport = SessionEffectReport() }
    }
    func shutdown() { stopped = true; clear(status: "会话已退出") }

    private func clear(status: String) {
        generation = UUID(); plan = nil; deadline = nil; isActive = false; isStarting = false
        effects.release(); effectReport = SessionEffectReport(); self.status = status
        downloadProgressObserver.stop(); downloadProgressPercent = nil
        downloadStamp = nil; downloadStableSince = nil; downloadObservedProgress = false; downloadObservedURL = nil; downloadFinalBaseline = nil
    }

    func tick(now: Date) async {
        guard !stopped else { effects.release(); return }
        guard workingProvider?() == true else {
            if isActive {
                // Disarm before awaiting: subsequent ticks must not request another
                // teardown. The coordinator releases its owned inhibitors before
                // asking the user to restore a changed lock policy.
                clear(status: "工作状态未通过核验，会话已停止")
                await onEnd?()
                // Do not mutate state after the callback: a manual mode change
                // may have taken ownership while its asynchronous cleanup awaited.
            } else { effects.release(); effectReport = SessionEffectReport() }
            return
        }
        guard isActive, let plan else {
            effectReport = effects.update(working: true, choices: choices, directories: driveDirectories, now: now)
            return
        }
        var finished = false
        switch plan {
        case .indefinite: status = "会话进行中 · 手动结束"
        case .deadline(let value): finished = now >= value; status = sessionStatus(now: now)
        case .application(let url):
            switch applicationProbe(url) {
            case .running(let pids):
                if pids.isEmpty { finished = true }
                else { status = "等待 \(url.deletingPathExtension().lastPathComponent) 退出" }
            case .absent: finished = true
            case .unavailable: status = "暂时无法核验应用，会话继续等待"
            }
        case .process(let process):
            switch processProbe(process.identity) {
            case .running: status = "等待 \(process.name)（PID \(process.identity.pid)）结束"
            case .exited: finished = true
            case .unavailable: status = "暂时无法核验所选进程，会话继续等待"
            }
        case .download(let url): finished = observeDownload(url, now: now)
        }
        if finished {
            clear(status: "会话条件已满足，正在恢复正常模式…")
            let token = generation
            await onEnd?()
            if generation == token { status = "会话已结束" }
            return
        }
        // Effects never substitute for the coordinator's verified system-sleep/lock contract.
        effectReport = effects.update(working: workingProvider?() == true, choices: choices, directories: driveDirectories, now: now)
    }

    private func sessionStatus(now: Date) -> String {
        guard let deadline else { return "会话进行中" }
        let minutes = max(0, Int(ceil(deadline.timeIntervalSince(now) / 60)))
        return "会话进行中 · 剩余 \(minutes) 分钟"
    }

    private func observeDownload(_ original: URL, now: Date) -> Bool {
        let partial = Self.isPartial(original)
        var url = original
        var reading = downloadProbe(url)
        if partial, case .missing = reading {
            url = original.deletingPathExtension(); reading = downloadProbe(url)
            if case .file(let final) = reading {
                // Cancelling a partial download can leave an unrelated, older
                // destination behind. Its mere presence is not completion.
                if reading == downloadFinalBaseline {
                    downloadStableSince = nil
                    status = "临时文件已消失，但原目标文件没有变化；继续等待"
                    return false
                }
                if downloadFinalBaseline == .unavailable, final.identity != downloadStamp?.identity {
                    downloadStableSince = nil
                    status = "无法确认重命名后的文件身份；继续等待"
                    return false
                }
            }
        }
        guard case .file(let stamp) = reading else {
            downloadStableSince = nil
            status = reading == .missing ? "文件暂不可见，等待下载进展或完成后的重命名" : "无法读取文件，完成判断已暂停"
            return false
        }
        if let previous = downloadStamp {
            if stamp.bytes > previous.bytes {
                downloadObservedProgress = true
            }
            if stamp != previous || downloadObservedURL != url || downloadStableSince == nil { downloadStableSince = now }
        } else {
            if stamp.bytes > 0 { downloadObservedProgress = true }
            downloadStableSince = now
        }
        downloadStamp = stamp; downloadObservedURL = url
        guard downloadObservedProgress else { status = "等待文件实际增长 · 已存在的静止文件不会被视为完成"; return false }
        guard !(partial && url == original) else { status = "文件仍有下载临时后缀，等待完成后的重命名"; return false }
        guard stamp.bytes > 0, let stable = downloadStableSince else { status = "等待有效下载内容"; return false }
        let elapsed = max(0, now.timeIntervalSince(stable))
        status = "已观察到下载进展 · 等待文件稳定 \(max(0, Int(ceil(downloadStabilitySeconds - elapsed)))) 秒"
        return elapsed >= downloadStabilitySeconds
    }
    private static func isPartial(_ url: URL) -> Bool { ["crdownload", "part", "partial", "download", "tmp"].contains(url.pathExtension.lowercased()) }

    // Safari moves the same-named payload out of its .download package when
    // finished. Track the package even when the user selects its inner file.
    nonisolated private static func downloadContainer(_ url: URL) -> URL {
        let parent = url.deletingLastPathComponent()
        return parent.pathExtension.lowercased() == "download"
            && parent.deletingPathExtension().lastPathComponent == url.lastPathComponent ? parent : url
    }

    nonisolated static func readApplication(_ url: URL) -> SessionApplicationReading {
        guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier,
              FileManager.default.fileExists(atPath: url.path) else { return .unavailable }
        let expected = url.standardizedFileURL.resolvingSymlinksInPath()
        let pids = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.bundleIdentifier == identifier && $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == expected
        }.map(\.processIdentifier)
        return pids.isEmpty ? .absent : .running(pids.sorted())
    }
    nonisolated static func readDownload(_ url: URL) -> SessionDownloadReading {
        do {
            var attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            if attrs[.type] as? FileAttributeType == .typeDirectory, url.pathExtension.lowercased() == "download" {
                let payload = url.appendingPathComponent(url.deletingPathExtension().lastPathComponent)
                // Read only the explicitly selected payload, never private
                // browser metadata or arbitrary files inside the package.
                guard let payloadAttrs = try? FileManager.default.attributesOfItem(atPath: payload.path) else { return .unavailable }
                attrs = payloadAttrs
            }
            guard attrs[.type] as? FileAttributeType == .typeRegular,
                  let size = attrs[.size] as? NSNumber, let modified = attrs[.modificationDate] as? Date,
                  let identity = attrs[.systemFileNumber] as? NSNumber else { return .unavailable }
            return .file(SessionFileStamp(bytes: size.int64Value, modified: modified, identity: identity.uint64Value))
        } catch {
            let value = error as NSError
            if value.domain == NSCocoaErrorDomain && value.code == NSFileReadNoSuchFileError { return .missing }
            return .unavailable
        }
    }

    nonisolated static func readRunningBundleIdentifier(_ identifier: String) -> SessionApplicationReading {
        let pids = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated && $0.bundleIdentifier == identifier }.map(\.processIdentifier)
        return pids.isEmpty ? .absent : .running(pids)
    }
    func chooseScreenSaverException() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "添加屏保例外"; panel.message = "此应用运行时暂停本应用的自动屏保，仍保留即时锁定保护。"
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier,
           !id.isEmpty, !screenSaverExceptionBundleIDs.contains(id) { screenSaverExceptionBundleIDs.append(id) }
    }
    func screenSaverExceptionName(_ identifier: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)?.deletingPathExtension().lastPathComponent ?? identifier
    }
    func chooseApplication() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "选择应用"; panel.message = "选择当前正在运行的应用；其所有匹配实例退出后结束会话。"
        if panel.runModal() == .OK { applicationURL = panel.url }
    }
    func chooseDownload() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "监测文件"; panel.message = "选择正在写入的下载文件或 Safari 的 .download 文件。观察到增长并完成重命名后，达到所设稳定时长才结束；网络暂停也可能被视为稳定。"
        if panel.runModal() == .OK { downloadURL = panel.url }
    }
    func chooseDriveDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "添加目录"; panel.message = "仅选择本地磁盘目录；工作期间按所设间隔写入并同步一个临时小文件，然后删除。"
        if panel.runModal() == .OK, let url = panel.url, !driveDirectories.contains(url) { driveDirectories.append(url) }
    }
    func requestCursorAccess() { NativeSessionEffects.requestAccessibility() }
}
