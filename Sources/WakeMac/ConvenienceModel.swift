import AppKit
import WakeMacCore

@MainActor enum AppPaths {
    // Retain the original storage location so a renamed installation keeps its history.
    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/WorkModes", isDirectory: true)
}

extension AppModel {
    var countdownText: String? {
        guard let end = [automation.nextDeadline, sessions.deadline].compactMap({ $0 }).min() else { return nil }
        let seconds = max(0, Int(ceil(end.timeIntervalSince(now))))
        if automation.batterySleepAt == end { return "低电量：\(seconds) 秒后休眠" }
        if automation.jobSleepAt == end { return "任务已完成：\(seconds) 秒后休眠" }
        return "\(max(1, Int(ceil(Double(seconds) / 60)))) 分钟后恢复正常模式"
    }
    var menuText: String {
        guard menuLabelEnabled else { return "" }
        if busy { return "切换中" }
        if error || pending != nil { return "待处理" }
        let name = active.map { $0 == .background ? "后台" : $0 == .desk ? "桌面" : "正常" } ?? "未知"
        guard let end = [automation.nextDeadline, sessions.deadline].compactMap({ $0 }).min() else { return name }
        if appearance.showEndTime {
            let formatter = DateFormatter(); formatter.dateFormat = appearance.twentyFourHour ? "HH:mm" : "h:mm a"
            return name + " · " + formatter.string(from: end)
        }
        return name + " · \(max(1, Int(ceil(end.timeIntervalSince(now) / 60))))m"
    }
    func record(_ text: String, notify: Bool = false) {
        historyStore.append(text); history = historyStore.entries
        if notify { notificationHandler?(text) }
    }
    func scheduleRestore(at date: Date) {
        guard !busy, active == .desk || active == .background else {
            convenienceMessage = "请先选择后台工作或桌面工作。"; return
        }
        guard date > Date() else { convenienceMessage = "请选择未来的时间。"; return }
        automation.deadline = date
        convenienceMessage = "已设置定时恢复。"
        record("定时恢复：" + date.formatted(date: .abbreviated, time: .shortened))
        onUpdate?()
    }
    func cancelVisibleCountdown() {
        guard let next = [automation.nextDeadline, sessions.deadline].compactMap({ $0 }).min() else { return }
        if sessions.deadline == next { Task { await sessions.end() }; return }
        if automation.batterySleepAt == next {
            automaticSleepRevision += 1; automation.cancelBatterySleep(); record("已取消本次低电量休眠。")
        } else if automation.jobSleepAt == next {
            automaticSleepRevision += 1; automation.cancelJobSleep(); record("已取消任务完成后休眠。")
        } else { cancelTimer() }
        onUpdate?()
    }
    func cancelTimer() {
        automation.deadline = nil; record("已取消定时恢复。"); onUpdate?()
    }
    func cancelAutomaticSleep() {
        automaticSleepRevision += 1
        automation.cancelBatterySleep(); automation.cancelJobSleep()
        convenienceMessage = "已取消自动休眠；正在运行的命令会继续。"
        record(convenienceMessage); onUpdate?()
    }
    func setBatteryProtection(enabled: Bool, threshold: Int) {
        automaticSleepRevision += 1
        automation.batteryEnabled = enabled
        automation.batteryThreshold = min(50, max(5, threshold))
        automation.resetBatterySession()
        preferences.set(enabled, forKey: "BatteryProtection")
        preferences.set(automation.batteryThreshold, forKey: "BatteryThreshold")
        record("低电量保护" + (enabled ? "：\(automation.batteryThreshold)%" : "已关闭"))
    }
    func setMenuLabel(_ enabled: Bool) {
        menuLabelEnabled = enabled; preferences.set(enabled, forKey: "MenuLabel"); onUpdate?()
    }
    func tick(now date: Date = Date(), battery reading: BatteryReading?) async {
        now = date; battery = reading; onUpdate?()
        guard !busy else { return }
        let actions = automation.evaluate(now: date, mode: active, battery: reading)
        for action in actions {
            switch action {
            case .restoreNormal:
                record("定时到点，恢复正常模式。", notify: true)
                await choose(.normal, automatic: true)
            case .batteryWarning(let percent):
                record("电量 \(percent)%，低于 \(automation.batteryThreshold)% 时将倒计时休眠。", notify: true)
            case .batteryCountdown:
                record("低电量保护：60 秒后休眠，可在面板取消。", notify: true)
            case .sleepForBattery:
                record("低电量保护开始恢复正常模式并请求休眠。", notify: true)
                await choose(.normal, sleep: true, automatic: true, batterySleep: true)
            case .sleepForJob:
                record("任务成功，开始恢复正常模式并请求休眠。", notify: true)
                await choose(.normal, sleep: true, automatic: true)
            }
        }
        await tickFeatures(now: date, battery: reading)
    }
    func startJob(command: String, directory: String) async {
        guard !jobRunning, !busy else { return }
        let path = (directory as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            convenienceMessage = "请填写命令和有效工作目录。"; return
        }
        jobRunning = true
        if active != .background && active != .desk { await choose(.desk) }
        guard !error, pending == nil, active == .desk || active == .background else {
            jobRunning = false; convenienceMessage = "工作模式未核验，未启动命令。"; return
        }
        let id = automation.beginJob()
        let log = jobLogDirectory.appendingPathComponent("task-\(id.uuidString).log")
        do { try FileManager.default.createDirectory(at: jobLogDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { jobRunning = false; automation.cancelJobSleep(); convenienceMessage = error.localizedDescription; return }
        jobStatus = "命令运行中"; jobLogURL = log; convenienceMessage = ""
        preferences.set(true, forKey: "JobWasRunning")
        record("命令任务已启动，成功后倒计时休眠。")
        do {
            let result = try await Task.detached(priority: .utility) {
                try CommandJob.run(command: command, directory: path, logURL: log)
            }.value
            completeJob(id: id, exitCode: result.exitCode, at: Date())
            if result.truncated { record("任务日志已达到 5 MB 上限，后续输出已丢弃。") }
        } catch {
            completeJob(id: id, exitCode: nil, at: Date())
            convenienceMessage = "命令启动或日志处理失败：" + error.localizedDescription
        }
    }
    func completeJob(id: UUID, exitCode: Int32?, at date: Date) {
        jobRunning = false; preferences.set(false, forKey: "JobWasRunning")
        automation.finishJob(id: id, success: exitCode == 0, now: date)
        if exitCode == 0 {
            jobStatus = automation.jobSleepAt == nil ? "命令成功；自动休眠已取消" : "命令成功；60 秒后休眠"
        } else { jobStatus = "命令失败（\(exitCode.map(String.init) ?? "未获得退出码")），不会休眠" }
        record(jobStatus, notify: true); onUpdate?()
    }
    func observeDisplay(_ updated: DisplayState) {
        if let old = display.lidClosed, let value = updated.lidClosed, old != value { record(value ? "检测到合盖。" : "检测到开盖。") }
        if let old = display.builtInAsleep, let value = updated.builtInAsleep, old != value { record(value ? "检测到屏幕熄灭。" : "检测到屏幕亮起。") }
        display = updated
    }
}
