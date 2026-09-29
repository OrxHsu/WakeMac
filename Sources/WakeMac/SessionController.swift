import AppKit
import Combine
import WakeMacCore

/// Session plans are configuration only. Active sessions are deliberately never persisted.
enum SessionEndCondition: String, CaseIterable, Identifiable {
    case indefinite, duration, untilDate, application, download
    var id: String { rawValue }
    var title: String {
        switch self {
        case .indefinite: return "手动结束"
        case .duration: return "持续一段时间"
        case .untilDate: return "到指定时间"
        case .application: return "直到应用退出"
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

@MainActor final class SessionController: ObservableObject {
    @Published var endCondition: SessionEndCondition = .indefinite
    @Published var durationMinutes: Double = 60
    @Published var endDate = Date().addingTimeInterval(3600)
    @Published var applicationURL: URL?
    @Published var downloadURL: URL?
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

    var onBegin: ((WorkMode) async -> Bool)?
    var onEnd: (() async -> Void)?
    var workingProvider: (() -> Bool)?
    var applicationProbe: (URL) -> SessionApplicationReading = SessionController.readApplication
    var downloadProbe: (URL) -> SessionDownloadReading = SessionController.readDownload
    private let preferences: UserDefaults
    private let effects: SessionEffectManaging
    private var generation = UUID()
    private var stopped = false
    private var plan: SessionPlan?
    private var downloadStamp: SessionFileStamp?
    private var downloadObservedProgress = false
    private var downloadStableSince: Date?
    private var downloadObservedURL: URL?
    private var downloadFinalBaseline: SessionDownloadReading?
    private let stabilityPeriod: TimeInterval = 30

    private enum SessionPlan { case indefinite, deadline(Date), application(URL), download(URL) }
    init(preferences: UserDefaults, effects: SessionEffectManaging? = nil) {
        self.preferences = preferences
        self.effects = effects ?? NativeSessionEffects()
        defaultMode = preferences.string(forKey: "session.defaultMode") == "background" ? .background : .desk
        preventDisplaySleep = preferences.bool(forKey: "session.preventDisplaySleep")
        preventScreenSaver = preferences.bool(forKey: "session.preventScreenSaver")
        driveAlive = preferences.bool(forKey: "session.driveAlive")
        driveDirectories = (preferences.stringArray(forKey: "session.driveDirectories") ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var choices: SessionEffectChoices {
        SessionEffectChoices(preventDisplaySleep: preventDisplaySleep, preventScreenSaver: preventScreenSaver, moveCursor: moveCursor, driveAlive: driveAlive)
    }
    private func saveChoices() {
        preferences.set(preventDisplaySleep, forKey: "session.preventDisplaySleep")
        preferences.set(preventScreenSaver, forKey: "session.preventScreenSaver")
        preferences.set(driveAlive, forKey: "session.driveAlive")
    }

    func start(now: Date = Date()) async {
        guard !stopped, !isActive, !isStarting else { return }
        effects.release(); effectReport = SessionEffectReport()
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
        case .download:
            guard let url = downloadURL else { status = "请先选择正在下载的文件"; return }
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
        status = "已观察到下载进展 · 等待文件稳定 \(max(0, Int(ceil(stabilityPeriod - elapsed)))) 秒"
        return elapsed >= stabilityPeriod
    }
    private static func isPartial(_ url: URL) -> Bool { ["crdownload", "part", "partial", "download", "tmp"].contains(url.pathExtension.lowercased()) }

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
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
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

    func chooseApplication() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "选择应用"; panel.message = "选择当前正在运行的应用；其所有匹配实例退出后结束会话。"
        if panel.runModal() == .OK { applicationURL = panel.url }
    }
    func chooseDownload() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.prompt = "监测文件"; panel.message = "选择正在写入的下载文件。必须观察到进展，并稳定 30 秒才结束；网络暂停也可能被视为稳定。"
        if panel.runModal() == .OK { downloadURL = panel.url }
    }
    func chooseDriveDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "添加目录"; panel.message = "仅选择本地磁盘目录；会话期间每分钟写入并同步一个临时小文件，然后删除。"
        if panel.runModal() == .OK, let url = panel.url, !driveDirectories.contains(url) { driveDirectories.append(url) }
    }
    func requestCursorAccess() { NativeSessionEffects.requestAccessibility() }
}
