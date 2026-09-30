import SwiftUI
import AppKit
import ServiceManagement
import WakeMacCore

private enum PreferencePage: String, CaseIterable {
    case power = "工作模式", sessions = "工作会话", triggers = "自动触发", automation = "自动收尾", command = "命令任务", settings = "偏好设置", advanced = "主题外观", history = "运行记录"
    var icon: String {
        switch self { case .power: "sun.max"; case .sessions: "hourglass"; case .triggers: "bolt.badge.clock"; case .automation: "timer"; case .command: "terminal"; case .settings: "slider.horizontal.3"; case .advanced: "paintbrush.pointed"; case .history: "clock.arrow.circlepath" }
    }
    var subtitle: String {
        switch self {
        case .power: "保持唤醒，合盖继续；工作结束后安心休眠。"
        case .sessions: "设置保持唤醒多久，或在应用退出、下载完成后自动结束。"
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
    @Namespace private var navigationSelection
    @State private var date = Date().addingTimeInterval(3600)
    @State private var command = ""
    @State private var directory = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var shortcutDraft = ShortcutBinding.defaults
    @State private var shortcutEnabled = true
    private var canSchedule: Bool { !model.busy && model.active != nil && model.active != .normal }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    Text(page.rawValue).font(.system(size: 30, weight: .heavy)).accessibilityAddTraits(.isHeader)
                    Text(page == .power ? "01 / POWER CONTROL" : page.subtitle)
                        .font(page == .power ? TerminalStyle.mono(11) : WorkType.body)
                        .foregroundStyle(TerminalStyle.muted).lineLimit(2)
                    Spacer(minLength: 0)
                    if let battery = model.battery {
                        TerminalLabel("\(battery.percent)%", systemImage: battery.onBattery ? "battery.75percent" : "battery.100percent.bolt")
                            .font(TerminalStyle.mono(12)).fixedSize()
                    }
                }.padding(.vertical, 20)
                    .overlay(alignment: .bottom) { Rectangle().fill(TerminalStyle.line).frame(height: 1) }
                    .padding(.horizontal, 20).padding(.bottom, 14)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch page {
                        case .power:
                            PowerHomeView(model: model, sessions: model.sessions) { page = .sessions }
                        case .sessions:
                            SessionsView(controller: model.sessions)
                            IdlePolicyView(controller: model.idlePolicy, immediateAuthentication: model.snapshot?.lockPolicy == .immediate)
                        case .triggers: TriggersView(controller: model.triggers)
                        case .automation: timerTab
                        case .command: taskTab
                        case .settings: settingsTab
                        case .advanced: AdvancedView(appearance: model.appearance, notifier: notifier)
                        case .history: historyTab
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 20).terminalReveal()
                }.id(page).frame(maxWidth: .infinity)
                    .transition(.opacity)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: page)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 860, minHeight: 630)
        .background(TerminalStyle.paper)
        .font(WorkType.body).foregroundStyle(TerminalStyle.ink).tint(TerminalStyle.accent)
        .buttonStyle(TerminalButtonStyle()).focusEffectDisabled().preferredColorScheme(.light)
        .onAppear { shortcutDraft = hotkeys.bindings; shortcutEnabled = hotkeys.enabled }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WakeMac").font(TerminalStyle.display(29)).fixedSize()
                Text("POWER TERMINAL").font(TerminalStyle.mono(10)).tracking(2.1)
                    .foregroundStyle(TerminalStyle.muted)
            }.padding(.horizontal, 22).padding(.top, 28).padding(.bottom, 32)
            VStack(spacing: 5) {
                ForEach(PreferencePage.allCases, id: \.self) { item in
                    Button {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { page = item }
                    } label: {
                        HStack(spacing: 12) {
                            TerminalIcon(name: item.icon, size: 20).font(.system(size: 19)).frame(width: 24)
                            Text(item.rawValue).font(.system(size: 15, weight: page == item ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 17).frame(height: 46)
                            .foregroundStyle(page == item ? TerminalStyle.accent : TerminalStyle.ink)
                             .background {
                                if page == item {
                                    TerminalStyle.selection.matchedGeometryEffect(id: "navigation", in: navigationSelection)
                                }
                            }
                            .overlay(alignment: .leading) {
                                if page == item {
                                    Rectangle().fill(TerminalStyle.accent).frame(width: 3)
                                        .matchedGeometryEffect(id: "navigation-rule", in: navigationSelection)
                                }
                            }
                            .contentShape(Rectangle())
                    }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
                        .accessibilityAddTraits(page == item ? [.isSelected] : [])
                }
            }.padding(.horizontal, 14)
            Spacer(minLength: 18)
            VStack(alignment: .leading, spacing: 14) {
                Rectangle().fill(TerminalStyle.line.opacity(0.7)).frame(height: 1)
                TerminalLabel(model.lockSummary, systemImage: model.requiresImmediateLock ? "checkmark.shield" : "gearshape")
                    .font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 20).padding(.bottom, 24)
        }.frame(width: 206).frame(maxHeight: .infinity)
            .background(LinearGradient(colors: [.white, TerminalStyle.silver.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .trailing) { Rectangle().fill(TerminalStyle.line).frame(width: 1) }
            .overlay(TerminalBrackets().stroke(TerminalStyle.muted, lineWidth: 0.7).padding(12).allowsHitTesting(false))
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
                        }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0).disabled(!canSchedule).opacity(canSchedule ? 1 : 0.45)
                            .accessibilityLabel(minutes < 60 ? "30 分钟" : "\(minutes / 60) 小时")
                    }
                } }
                HStack(spacing: 10) {
                    SchedulePicker(selection: $date)
                    Spacer(minLength: 0)
                    Button("设置定时") { model.scheduleRestore(at: date) }.workKeyboardFocus(radius: 0).disabled(!canSchedule)
                }
                if let end = model.automation.deadline {
                    HStack {
                        TerminalLabel(end.formatted(date: .omitted, time: .shortened) + " 恢复正常模式", systemImage: "timer")
                            .foregroundStyle(WorkStyle.blue)
                        Spacer()
                        Button("取消", action: model.cancelTimer).buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
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
                    TerminalStepper(value: Binding(get: { model.automation.batteryThreshold }, set: { model.setBatteryProtection(enabled: model.automation.batteryEnabled, threshold: $0) }), in: 5...50, step: 5) {
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
                        TerminalIcon(name: battery.onBattery ? "battery.75percent" : "bolt.fill")
                        Text("当前 \(battery.percent)%")
                        Spacer()
                        Text(battery.onBattery ? "电池供电" : "已连接电源")
                    }.font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                }
            }
            if let text = model.countdownText {
                TerminalLabel(text, systemImage: "timer").foregroundStyle(WorkStyle.blue)
            }
            if model.automation.batterySleepAt != nil || model.automation.jobSleepAt != nil {
                Button("取消自动休眠", action: model.cancelAutomaticSleep).workKeyboardFocus(radius: 0)
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
                        }.workKeyboardFocus(radius: 0).disabled(model.jobRunning)
                    }
                }
                commandConsole
                if model.jobRunning || model.automation.jobSleepAt != nil {
                    Button("取消完成后休眠，命令继续", action: model.cancelAutomaticSleep).workKeyboardFocus(radius: 0)
                }
                if let url = model.jobLogURL {
                    Button("在 Finder 查看日志") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.workKeyboardFocus(radius: 0)
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

    private var commandConsole: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TerminalIcon(name: "terminal", size: 14).foregroundStyle(WorkStyle.blue)
                Text("zsh").font(.system(size: 11, weight: .medium, design: .monospaced))
                Text(directory.isEmpty ? "未选择工作目录" : directory)
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(WorkStyle.muted)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 12)
                Text(model.jobRunning ? "RUNNING" : "COMMAND")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(model.jobRunning ? WorkStyle.blue : WorkStyle.muted)
            }.padding(.horizontal, 12).padding(.vertical, 9)
                .background(TerminalStyle.silver.opacity(0.45))
            Rectangle().fill(WorkStyle.line).frame(height: 1)
            HStack(alignment: .top, spacing: 8) {
                Text("❯").font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WorkStyle.blue).frame(width: 18).padding(.top, 1)
                    .accessibilityHidden(true)
                ZStack(alignment: .topLeading) {
                    if command.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("# 在这里输入命令，支持多行")
                            Text("# 成功后倒计时休眠，失败时保留现场")
                        }.font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(TerminalStyle.steel)
                            .padding(.leading, 5).padding(.top, 1)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    TextEditor(text: $command).font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(WorkStyle.ink).scrollContentBackground(.hidden)
                        .frame(height: 132).disabled(model.jobRunning).focusEffectDisabled()
                        .accessibilityLabel("要运行的 zsh 命令")
                }
            }.padding(12).background(WorkStyle.canvas)
            Rectangle().fill(WorkStyle.line).frame(height: 1)
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Circle().fill(model.jobRunning ? WorkStyle.blue : TerminalStyle.amber).frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text(model.jobStatus).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(WorkStyle.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button { Task { await model.startJob(command: command, directory: directory) } } label: {
                    TerminalLabel("运行，成功后休眠", systemImage: "play.fill")
                }.buttonStyle(WorkButtonStyle(prominent: true)).workKeyboardFocus(radius: 0)
                    .disabled(model.jobRunning || model.busy || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(12).background(TerminalStyle.silver.opacity(0.2))
        }.overlay(Rectangle().strokeBorder(WorkStyle.line))
    }

    private var settingsTab: some View {
        Group {
            WorkCard(title: "合盖运行") {
                Text("合盖继续运行需要启用 WakeMac 自带的系统服务，并在系统设置中批准一次。")
                    .font(.system(size: 12)).foregroundStyle(WorkStyle.muted)
                HStack {
                    Button(model.helperStatus == .requiresApproval ? "完成授权…" : "启用合盖服务…", action: model.enableHelper).workKeyboardFocus(radius: 0)
                        .disabled(model.busy || model.helperStatus == .enabled)
                    Button("打开系统设置") { SMAppService.openSystemSettingsLoginItems() }.workKeyboardFocus(radius: 0)
                    Button("移除服务") { Task { await model.removeHelper() } }.workKeyboardFocus(radius: 0).disabled(model.busy)
                }
                WorkNote(text: model.helperStatus == .enabled ? "合盖服务已授权，可以选择后台工作。" : model.helperMessage.isEmpty ? "合盖服务尚未授权。" : model.helperMessage)
                WorkNote(text: "切换回正常模式或退出应用会恢复休眠；异常断线和心跳超时由服务自动恢复。")
            }
            WorkCard(title: "锁屏与密码", subtitle: "选择 WakeMac 核验工作模式时采用的锁屏策略。") {
                WorkToggle(title: "要求即时密码保护", detail: "默认开启。关闭后跟随 macOS 的密码要求，可使用系统设置的延迟或不要求密码。", isOn: Binding(get: { model.requiresImmediateLock }, set: { enabled in Task { await model.setRequireImmediateLock(enabled) } }))
                    .disabled(model.busy)
                HStack {
                    Text(model.lockSummary).font(WorkType.body).foregroundStyle(WorkStyle.muted)
                    Spacer()
                    Button("打开锁屏设置", action: model.openLockSettings).workKeyboardFocus(radius: 0)
                }
                WorkNote(text: "WakeMac 不修改系统密码要求，也不解锁已锁定的 Mac。系统设为不要求密码时，熄屏后返回桌面也不再要求密码。")
            }
            WorkCard(title: "日常使用") {
                WorkToggle(title: "菜单栏显示模式和倒计时", isOn: Binding(get: { model.menuLabelEnabled }, set: model.setMenuLabel))
                Rectangle().fill(WorkStyle.line).frame(height: 1)
                WorkToggle(title: "登录时启动", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
                Rectangle().fill(WorkStyle.line).frame(height: 1)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("系统通知").font(WorkType.controlLabel)
                        Text(notifier.enabled ? "通知已开启" : "接收任务结果与电量提醒").font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                    }
                    Spacer()
                    Button(notifier.enabled ? "通知设置…" : "开启通知…") {
                        if notifier.enabled { notifier.showSettings() }
                        else { Task { _ = await notifier.request() } }
                    }.workKeyboardFocus(radius: 0)
                }
                if !notifier.message.isEmpty { WorkNote(text: notifier.message) }
            }.toggleStyle(TerminalSwitchStyle()).controlSize(.small)
            WorkCard(title: "会话通知", subtitle: "任务结果、低电量与错误提醒继续保留。") {
                WorkToggle(title: "工作会话开始", isOn: $notifier.sessionStart)
                WorkToggle(title: "工作会话结束", isOn: $notifier.sessionEnd)
                WorkToggle(title: "自动触发开始与结束", isOn: $notifier.triggerChange)
                WorkToggle(title: "自动清理已显示的 WakeMac 通知", isOn: $notifier.autoClear)
            }
            WorkCard(title: "全局快捷键") {
                WorkToggle(title: "启用快捷键", isOn: $shortcutEnabled)
                ForEach(shortcutDraft.indices, id: \.self) { index in
                    HStack {
                        Text(shortcutDraft[index].title).font(WorkType.controlLabel)
                        Spacer()
                        Toggle("启用" + shortcutDraft[index].title, isOn: $shortcutDraft[index].enabled)
                            .labelsHidden().toggleStyle(TerminalSwitchStyle()).controlSize(.small)
                        TerminalPicker("修饰键", selection: $shortcutDraft[index].modifiers, choices: GlobalHotKeys.modifiers.map { TerminalChoice($0.0, $0.1) }).labelsHidden().frame(width: 108)
                        TerminalPicker("按键", selection: $shortcutDraft[index].key, choices: GlobalHotKeys.keys.map { TerminalChoice($0.0, $0.1) }).labelsHidden().frame(width: 66)
                    }
                }
                HStack {
                    Text(hotkeys.message.isEmpty ? "模式默认使用 ⌃⌥ + 1 / 2 / 3；其他操作按需开启。" : hotkeys.message)
                        .font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                    Spacer()
                    Button("保存快捷键") { hotkeys.apply(shortcutDraft, enabled: shortcutEnabled) }.workKeyboardFocus(radius: 0)
                }
            }
            BehaviorSettingsView(behavior: model.behavior)
            HStack {
                WorkNote(text: "退出前会恢复正常休眠。", icon: "power")
                Spacer()
                Button("提交问题") { if let url = URL(string: "https://github.com/OrxHsu/WakeMac/issues/new") { NSWorkspace.shared.open(url) } }.workKeyboardFocus(radius: 0)
                Button("退出 WakeMac") { Task { await model.requestQuit() } }.workKeyboardFocus(radius: 0).disabled(model.busy)
            }
            if model.jobRunning { WorkNote(text: "命令仍在运行，退出时会等待任务结束。") }
        }
    }

    private var historyTab: some View {
        Group {
            HStack {
                TerminalLabel("仅保存在这台 Mac", systemImage: "internaldrive")
                Spacer()
                Text("最近 \(model.history.count) 条 / 最多 200 条").monospacedDigit()
            }.font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
            if model.history.isEmpty {
                VStack(spacing: 12) {
                    TerminalIcon(name: "clock").font(.system(size: 28)).foregroundStyle(WorkStyle.blue)
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
