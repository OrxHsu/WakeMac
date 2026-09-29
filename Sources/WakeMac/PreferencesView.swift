import SwiftUI
import AppKit
import ServiceManagement
import WakeMacCore

private enum PreferencePage: String, CaseIterable {
    case power = "工作模式", sessions = "工作会话", triggers = "自动触发", automation = "自动收尾", command = "命令任务", settings = "偏好设置", advanced = "外观与脚本", history = "运行记录"
    var icon: String {
        switch self { case .power: "sun.max"; case .sessions: "hourglass"; case .triggers: "bolt.badge.clock"; case .automation: "timer"; case .command: "terminal"; case .settings: "slider.horizontal.3"; case .advanced: "paintbrush.pointed"; case .history: "clock.arrow.circlepath" }
    }
    var subtitle: String {
        switch self {
        case .power: "保持唤醒，合盖继续；工作结束后安心休眠。"
        case .sessions: "按时间、应用或下载，决定这次工作的结束。"
        case .triggers: "条件满足时自动开始，手动操作始终优先。"
        case .automation: "让工作按时结束，也照顾好电量。"
        case .command: "交给它一条命令，完成后安心休息。"
        case .settings: "按你的习惯，安排每一次切换。"
        case .advanced: "调整菜单栏与通知声音，或用脚本管理会话。"
        case .history: "模式切换与运行状态，都留在这里。"
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var hotkeys: GlobalHotKeys
    @ObservedObject var notifier: LocalNotifier
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = PreferencePage.power
    @State private var date = Date().addingTimeInterval(3600)
    @State private var command = ""
    @State private var directory = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var shortcutDraft = ShortcutBinding.defaults
    @State private var shortcutEnabled = true
    private var canSchedule: Bool { !model.busy && model.active != nil && model.active != .normal }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.padding(.leading, 12).padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(page.rawValue).font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(page.subtitle).font(.system(size: 12)).foregroundStyle(WorkStyle.muted)
                }.padding(.horizontal, 30).padding(.top, 32).padding(.bottom, 24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch page {
                        case .power: powerTab
                        case .sessions:
                            SessionsView(controller: model.sessions)
                            IdlePolicyView(controller: model.idlePolicy)
                        case .triggers: TriggersView(controller: model.triggers)
                        case .automation: timerTab
                        case .command: taskTab
                        case .settings: settingsTab
                        case .advanced: AdvancedView(appearance: model.appearance)
                        case .history: historyTab
                        }
                    }.padding(.horizontal, 28).padding(.bottom, 28)
                }
                .id(page)
                .frame(maxWidth: .infinity)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        }
        .frame(minWidth: 780, minHeight: 630)
        .background(WorkStyle.canvas)
        .font(.system(size: 12)).foregroundStyle(WorkStyle.ink).tint(WorkStyle.blue)
        .buttonStyle(WorkButtonStyle())
        .onAppear { shortcutDraft = hotkeys.bindings; shortcutEnabled = hotkeys.enabled }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: MenuMark.image()).renderingMode(.template).foregroundStyle(WorkStyle.blue)
                Text("WakeMac").font(.system(size: 14, weight: .semibold))
            }.padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 30)
            VStack(spacing: 5) {
                ForEach(PreferencePage.allCases, id: \.self) { item in
                    Button { withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { page = item } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon).font(.system(size: 14)).frame(width: 20)
                            Text(item.rawValue).font(.system(size: 12, weight: page == item ? .semibold : .medium))
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 12).padding(.vertical, 12)
                            .foregroundStyle(page == item ? WorkStyle.blue : WorkStyle.muted)
                            .background(page == item ? WorkStyle.blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).focusEffectDisabled()
                        .accessibilityAddTraits(page == item ? [.isSelected] : [])
                }
            }.padding(.horizontal, 10)
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(model.error ? Color.orange : WorkStyle.blue).frame(width: 5, height: 5)
                    Text(model.headline).font(.system(size: 11, weight: .medium))
                }
                Label("锁屏保护始终保留", systemImage: "lock.shield").font(.system(size: 10))
                    .foregroundStyle(WorkStyle.muted)
            }.padding(20)
        }.frame(width: 174).frame(maxHeight: .infinity).background(WorkGlassBackground(radius: 22))
    }

    private var powerTab: some View {
        Group {
            WorkCard(title: "运行控制", subtitle: model.headline) {
                PowerControls(model: model)
                HStack {
                    Button("工作会话") { page = .sessions }
                    Button("自动触发") { page = .triggers }
                    Spacer()
                }
                if model.sessions.isActive { WorkNote(text: model.sessions.status, icon: "hourglass") }
                if model.triggerOwnedMode != nil { WorkNote(text: model.triggerSummary, icon: "bolt.badge.clock") }
            }
            WorkCard(title: "快捷模式") {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(WorkMode.allCases, id: \.self) { mode in
                        Button {
                            model.quitWhenReady = false
                            Task { await model.choose(mode) }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: mode.icon).font(.system(size: 19))
                                    Spacer()
                                    if model.active == mode { Image(systemName: "checkmark.circle.fill") }
                                }.foregroundStyle(model.active == mode ? WorkStyle.blue : WorkStyle.muted)
                                Text(mode.title).font(.system(size: 12, weight: .semibold))
                                Text(mode == .background ? "保持唤醒\n合盖继续" : mode == .desk ? "保持唤醒\n允许合盖休眠" : "恢复闲置\n与合盖休眠")
                                    .font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(model.active == mode ? WorkStyle.selection : WorkStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).focusEffectDisabled()
                            .disabled(model.busy || (mode == .background && model.helperStatus != .enabled))
                            .accessibilityAddTraits(model.active == mode ? [.isSelected] : [])
                    }
                }
            }
            HStack {
                WorkNote(text: model.display.lidClosed.map { $0 ? "上盖已合上" : "上盖已打开" } ?? "上盖状态未知", icon: "laptopcomputer")
                Spacer()
                Button("立即休眠") { Task { await model.choose(.normal, sleep: true) } }.disabled(model.busy)
            }
            if model.pending != nil || model.error {
                WorkNote(text: model.message, icon: "exclamationmark.circle")
                HStack {
                    if model.pending != nil { Button("恢复锁屏保护", action: model.openLockSettings) }
                    Button("重新检查") { model.error = false; Task { await model.refresh() } }
                }
            }
        }
    }

    private var timerTab: some View {
        Group {
            WorkCard(title: "定时恢复", subtitle: "到点恢复正常模式，让 Mac 可以自然休眠。") {
                WorkGlassGroup { HStack(spacing: 12) {
                    ForEach([30, 60, 120], id: \.self) { minutes in
                        Button { model.scheduleRestore(at: Date().addingTimeInterval(Double(minutes * 60))) } label: {
                            VStack(spacing: 4) {
                                Text(minutes < 60 ? "30" : "\(minutes / 60)").font(.system(size: 25, weight: .medium, design: .rounded))
                                Text(minutes < 60 ? "分钟后" : "小时后").font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                            }.frame(maxWidth: .infinity).padding(.vertical, 12)
                                .workGlassControl()
                        }.buttonStyle(.plain).disabled(!canSchedule).opacity(canSchedule ? 1 : 0.45)
                            .accessibilityLabel(minutes < 60 ? "30 分钟" : "\(minutes / 60) 小时")
                    }
                } }
                HStack(spacing: 10) {
                    SchedulePicker(selection: $date)
                    Spacer(minLength: 0)
                    Button("设置定时") { model.scheduleRestore(at: date) }.disabled(!canSchedule)
                }
                if let end = model.automation.deadline {
                    HStack {
                        Label(end.formatted(date: .omitted, time: .shortened) + " 恢复正常模式", systemImage: "timer")
                            .foregroundStyle(WorkStyle.blue)
                        Spacer()
                        Button("取消", action: model.cancelTimer).buttonStyle(.plain)
                    }
                } else if !canSchedule {
                    WorkNote(text: "先在工作模式页或菜单栏开启保持唤醒，再设置定时。")
                }
            }
            WorkCard(title: "低电量保护") {
                WorkToggle(title: "电池供电时自动保护", isOn: Binding(get: { model.automation.batteryEnabled }, set: { model.setBatteryProtection(enabled: $0, threshold: model.automation.batteryThreshold) }))
                HStack {
                    Text("休眠电量").foregroundStyle(WorkStyle.muted)
                    Spacer()
                    Stepper(value: Binding(get: { model.automation.batteryThreshold }, set: { model.setBatteryProtection(enabled: model.automation.batteryEnabled, threshold: $0) }), in: 5...50, step: 5) {
                        Text("\(model.automation.batteryThreshold)%").font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit()
                    }.fixedSize().accessibilityLabel("休眠电量")
                }
                WorkNote(text: "到达阈值后，留出 60 秒取消。接上电源会自动取消休眠。", icon: "battery.25percent")
                DisclosureGroup("保护规则") {
                    Text("提前 5% 提醒；倒计时结束后先恢复正常模式，再请求休眠。取消后本次工作模式不重复触发，重新选择工作模式即可恢复保护。")
                        .font(.system(size: 11)).foregroundStyle(WorkStyle.muted).padding(.top, 6)
                }.font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                if let battery = model.battery {
                    HStack {
                        Image(systemName: battery.onBattery ? "battery.75percent" : "bolt.fill")
                        Text("当前 \(battery.percent)%")
                        Spacer()
                        Text(battery.onBattery ? "电池供电" : "已连接电源")
                    }.font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                }
            }
            if let text = model.countdownText {
                Label(text, systemImage: "timer").foregroundStyle(WorkStyle.blue)
            }
            if model.automation.batterySleepAt != nil || model.automation.jobSleepAt != nil {
                Button("取消自动休眠", action: model.cancelAutomaticSleep)
            }
            feedback
        }
    }

    private var taskTab: some View {
        Group {
            WorkCard(title: "运行一次，完成后休眠", subtitle: "命令成功后倒计时 60 秒；失败时保留现场。") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("工作目录").font(.system(size: 11, weight: .medium)).foregroundStyle(WorkStyle.muted)
                    HStack(spacing: 8) {
                        TextField("工作目录", text: $directory).textFieldStyle(.plain).padding(10)
                            .background(WorkStyle.canvas, in: RoundedRectangle(cornerRadius: WorkStyle.inputRadius))
                            .disabled(model.jobRunning)
                        Button("选择…") {
                            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url { directory = url.path }
                        }.disabled(model.jobRunning)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("命令").font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("zsh").font(.system(size: 10, design: .monospaced))
                    }.foregroundStyle(WorkStyle.muted)
                    TextEditor(text: $command).font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden).padding(10).frame(height: 120)
                        .background(WorkStyle.canvas, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WorkStyle.line))
                        .disabled(model.jobRunning).accessibilityLabel("要运行的 zsh 命令")
                }
                HStack {
                    Label(model.jobStatus, systemImage: model.jobRunning ? "circle.dotted" : "terminal")
                        .font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                    Spacer()
                    Button { Task { await model.startJob(command: command, directory: directory) } } label: {
                        Label("运行，成功后休眠", systemImage: "play.fill")
                    }.buttonStyle(WorkButtonStyle(prominent: true))
                        .disabled(model.jobRunning || model.busy || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if model.jobRunning || model.automation.jobSleepAt != nil {
                    Button("取消完成后休眠，命令继续", action: model.cancelAutomaticSleep)
                }
                if let url = model.jobLogURL {
                    Button("在 Finder 查看日志") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
            WorkNote(text: "只跟踪这里启动的命令，不会判断其他 Codex 任务是否完成。")
            DisclosureGroup("运行前须知") {
                Text("未处于工作模式时会先切换到桌面工作。使用非交互的前台命令，不支持密码输入或 & / nohup 后台任务。日志保留输出的前 5 MB。")
                    .font(.system(size: 11)).foregroundStyle(WorkStyle.muted).padding(.top, 8)
            }.font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
            feedback
        }
    }

    private var settingsTab: some View {
        Group {
            WorkCard(title: "合盖运行") {
                Text("合盖继续运行需要启用 WakeMac 自带的系统服务，并在系统设置中批准一次。")
                    .font(.system(size: 12)).foregroundStyle(WorkStyle.muted)
                HStack {
                    Button(model.helperStatus == .requiresApproval ? "完成授权…" : "启用合盖服务…", action: model.enableHelper)
                        .disabled(model.busy || model.helperStatus == .enabled)
                    Button("打开系统设置") { SMAppService.openSystemSettingsLoginItems() }
                    Button("移除服务") { Task { await model.removeHelper() } }.disabled(model.busy)
                }
                WorkNote(text: model.helperStatus == .enabled ? "合盖服务已授权，可以选择后台工作。" : model.helperMessage.isEmpty ? "合盖服务尚未授权。" : model.helperMessage)
                WorkNote(text: "切换回正常模式或退出应用会恢复休眠；异常断线和心跳超时由服务自动恢复。")
            }
            WorkCard(title: "日常使用") {
                WorkToggle(title: "菜单栏显示模式和倒计时", isOn: Binding(get: { model.menuLabelEnabled }, set: model.setMenuLabel))
                Rectangle().fill(WorkStyle.line).frame(height: 1)
                WorkToggle(title: "登录时启动", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
                Rectangle().fill(WorkStyle.line).frame(height: 1)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("系统通知")
                        Text(notifier.enabled ? "通知已开启" : "接收任务结果与电量提醒").font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                    }
                    Spacer()
                    Button(notifier.enabled ? "通知设置…" : "开启通知…") {
                        if notifier.enabled { notifier.showSettings() }
                        else { Task { _ = await notifier.request() } }
                    }
                }
                if !notifier.message.isEmpty { WorkNote(text: notifier.message) }
            }.toggleStyle(.switch).controlSize(.small)
            WorkCard(title: "全局快捷键") {
                WorkToggle(title: "启用快捷键", isOn: $shortcutEnabled)
                ForEach(shortcutDraft.indices, id: \.self) { index in
                    HStack {
                        Text(shortcutDraft[index].title)
                        Spacer()
                        Picker("修饰键", selection: $shortcutDraft[index].modifiers) {
                            ForEach(GlobalHotKeys.modifiers, id: \.1) { Text($0.0).tag($0.1) }
                        }.labelsHidden().frame(width: 108)
                        Picker("按键", selection: $shortcutDraft[index].key) {
                            ForEach(GlobalHotKeys.keys, id: \.1) { Text($0.0).tag($0.1) }
                        }.labelsHidden().frame(width: 66)
                    }
                }
                HStack {
                    Text(hotkeys.message.isEmpty ? "默认使用 ⌃⌥ + 1 / 2 / 3" : hotkeys.message)
                        .font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                    Spacer()
                    Button("保存快捷键") { hotkeys.apply(shortcutDraft, enabled: shortcutEnabled) }
                }
            }
            HStack {
                WorkNote(text: "退出前会恢复正常休眠。", icon: "power")
                Spacer()
                Button("退出 WakeMac") { Task { await model.requestQuit() } }.disabled(model.busy)
            }
            if model.jobRunning { WorkNote(text: "命令仍在运行，退出时会等待任务结束。") }
        }
    }

    private var historyTab: some View {
        Group {
            HStack {
                Label("仅保存在这台 Mac", systemImage: "internaldrive")
                Spacer()
                Text("最近 \(model.history.count) 条 / 最多 200 条").monospacedDigit()
            }.font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
            if model.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock").font(.system(size: 28)).foregroundStyle(WorkStyle.blue)
                    Text("还没有运行记录").font(.system(size: 14, weight: .medium))
                    Text("切换模式后，记录会出现在这里。").foregroundStyle(WorkStyle.muted)
                }.frame(maxWidth: .infinity).padding(.vertical, 60)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.history) { entry in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.date.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                Text(entry.date.formatted(.dateTime.month().day())).font(.system(size: 10))
                            }.foregroundStyle(WorkStyle.muted).frame(width: 60, alignment: .leading)
                            Text(entry.text).font(.system(size: 12)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        }.padding(16)
                        Rectangle().fill(WorkStyle.line).frame(height: 1).padding(.horizontal, 16)
                    }
                }.background(WorkStyle.surface, in: RoundedRectangle(cornerRadius: WorkStyle.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: WorkStyle.cardRadius).strokeBorder(WorkStyle.line.opacity(0.5)))
            }
            WorkNote(text: "合盖与屏幕状态约每 10 秒采样；休眠和唤醒按系统事件记录。")
        }
    }

    @ViewBuilder private var feedback: some View {
        if !model.convenienceMessage.isEmpty { WorkNote(text: model.convenienceMessage) }
    }
}
