import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WakeMacCore

struct TriggersView: View {
    @ObservedObject var controller: TriggerController
    @State private var editing: TriggerRule?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WorkCard(title: "触发规则", subtitle: "条件满足时进入工作模式，条件结束时由会话恢复策略处理。所有规则默认关闭；锁屏策略跟随偏好设置。") {
                WorkToggle(title: "启用自动触发", detail: "暂停时保留规则设置，并停止自动匹配。", isOn: $controller.enabled)
                HStack {
                    Text(controller.status).font(.system(size: 12)).foregroundStyle(WorkStyle.muted)
                    Spacer()
                    Button("新建规则") { editing = TriggerRule() }.buttonStyle(WorkButtonStyle(prominent: true)).workKeyboardFocus(radius: 0)
                }
                if controller.rules.isEmpty { Text("添加一条规则，选择触发条件并保存，然后主动启用。") .font(.system(size: 12)).foregroundStyle(WorkStyle.muted) }
                ForEach(controller.rules) { rule in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            WorkToggle(title: rule.name, detail: (rule.mode == .background ? "后台工作" : "桌面工作") + " · " + (rule.combination == .all ? "所有条件" : "任一条件"), isOn: Binding(get: { rule.enabled }, set: { controller.setEnabled(rule.id, $0) }))
                            Spacer()
                            Button("编辑") { editing = rule }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                            Button("删除", role: .destructive) { controller.remove(rule.id) }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                        }
                        ForEach(rule.conditions) { condition in
                            let reading = controller.observations[condition.id]
                            HStack(alignment: .top, spacing: 8) {
                                TerminalIcon(name: reading?.state == .matched ? "checkmark.circle.fill" : reading?.state == .unknown ? "questionmark.circle" : "circle")
                                    .foregroundStyle(reading?.state == .matched ? WorkStyle.blue : WorkStyle.muted)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(conditionTitle(condition))
                                    if let reading { Text((reading.state == .unknown ? "未知 · " : reading.state == .matched ? "满足 · " : "未满足 · ") + reading.detail).foregroundStyle(WorkStyle.muted).textSelection(.enabled) }
                                }.font(.system(size: 11))
                            }
                        }
                    }.padding(.vertical, 10)
                    if rule.id != controller.rules.last?.id { Rectangle().fill(WorkStyle.line).frame(height: 1) }
                }
            }
            WorkCard(title: "当前观测", subtitle: "只读诊断不会切换电源模式。CPU 第一次采样不可判定；再次刷新后显示两次采样间的使用率。") {
                HStack {
                    Button("刷新观测") { Task { await controller.refreshDiagnostics() } }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                    if let date = controller.lastObservedAt { Text(date.formatted(date: .omitted, time: .standard)).font(.system(size: 11)).foregroundStyle(WorkStyle.muted) }
                }
                if controller.rules.contains(where: { $0.conditions.contains(where: { $0.kind == .wifiSSID }) }) { permissionRow(kind: .wifiSSID, title: "Wi-Fi 网络名称", explanation: "macOS 需要定位权限才会提供网络名称。拒绝或未授权时不会匹配。") }
                if controller.rules.contains(where: { $0.conditions.contains(where: { $0.kind == .bluetoothDevice }) }) { permissionRow(kind: .bluetoothDevice, title: "蓝牙设备", explanation: "仅读取系统已配对且当前连接的设备。需要蓝牙权限。") }
                WorkNote(text: "Cisco VPN 仅匹配系统 VPN 服务提供的连接状态；未公开状态的客户端显示未知。耳机条件读取内置输出的耳机标识，USB 或蓝牙耳机请使用指定音频输出。")
            }
        }.sheet(item: $editing) { rule in TriggerRuleEditor(rule: rule, controller: controller) }
    }
    private func conditionTitle(_ condition: TriggerCondition) -> String {
        if condition.kind == .weeklySchedule { return condition.kind.title + "：" + (condition.schedule?.summary ?? "尚未设置") }
        if condition.kind == .externalDisplay && !condition.ignoreBuiltInDisplay { return "连接显示器（包括内建）" }
        if condition.kind == .processRunning { return condition.kind.title + "：" + URL(fileURLWithPath: condition.value).lastPathComponent }
        guard condition.kind.requiresValue else { return condition.kind.title }
        if (condition.kind == .appRunning || condition.kind == .appFrontmost),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: condition.value) {
            return condition.kind.title + "：" + FileManager.default.displayName(atPath: url.path)
        }
        return condition.kind.title + "：" + condition.value
    }
    private func permissionRow(kind: TriggerKind, title: String, explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(WorkType.controlLabel)
            Text(explanation).font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
            HStack {
                Button("请求授权") { controller.requestPermission(for: kind) }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                Button("打开权限设置") { controller.openPermissionSettings(for: kind) }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
            }
        }
    }
}

private struct TriggerRuleEditor: View {
    @State var rule: TriggerRule
    @ObservedObject var controller: TriggerController
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var preview = TriggerSnapshot()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("编辑触发规则").font(WorkType.dialogTitle).accessibilityAddTraits(.isHeader)
            TextField("规则名称", text: $rule.name).textFieldStyle(TerminalTextFieldStyle())
            HStack {
                TerminalPicker("进入模式", selection: $rule.mode, choices: [TerminalChoice("桌面工作", .desk), TerminalChoice("后台工作", .background)])
                TerminalPicker("组合条件", selection: $rule.combination, choices: [TerminalChoice("所有条件都满足", .all), TerminalChoice("任一条件满足", .any)])
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach($rule.conditions) { $condition in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                TerminalPicker("条件", selection: $condition.kind, choices: TriggerKind.allCases.map { TerminalChoice($0.title, $0) })
                                Button("移除") { rule.conditions.removeAll { $0.id == condition.id } }.workKeyboardFocus(radius: 0).disabled(rule.conditions.count == 1)
                            }
                            if condition.kind == .weeklySchedule { scheduleInput($condition) }
                            if condition.kind == .externalDisplay {
                                WorkToggle(title: "忽略内建显示器", detail: "只把外接显示器作为匹配条件。", isOn: $condition.ignoreBuiltInDisplay)
                            }
                            if condition.kind.requiresValue {
                                conditionInput($condition)
                                if condition.kind != .appRunning && condition.kind != .appFrontmost {
                                    Text(condition.kind.hint).font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                                }
                            }
                            if let validation = condition.validationError { Text(validation).font(.system(size: 11)).foregroundStyle(.red) }
                        }.onChange(of: condition.kind) { _, kind in
                            if kind == .weeklySchedule && condition.schedule == nil { condition.schedule = TriggerWeeklySchedule() }
                        }.padding(12).background(WorkStyle.canvas, in: RoundedRectangle(cornerRadius: 0))
                    }
                }
            }.frame(minHeight: 160, maxHeight: 320)
            Button("添加条件") { rule.conditions.append(TriggerCondition()) }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
            VStack(alignment: .leading, spacing: 10) {
                Text("规则生效时的显示行为").font(WorkType.controlLabel)
                HStack {
                    TerminalPicker("显示器", selection: $rule.preventDisplaySleep, choices: [TerminalChoice("使用全局设置", nil), TerminalChoice("保持亮屏", true), TerminalChoice("允许闲时息屏", false)])
                    TerminalPicker("屏幕保护", selection: $rule.preventScreenSaver, choices: [TerminalChoice("使用全局设置", nil), TerminalChoice("暂停屏保", true), TerminalChoice("允许屏保", false)])
                }
                WorkNote(text: "覆盖仅在本规则控制工作模式时生效；系统锁定后亮屏与屏保保活会暂停，密码要求由所选锁屏策略决定。")
            }
            WorkToggle(title: "启用这条规则", detail: "启用后会开始自动匹配条件。", isOn: $rule.enabled)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                Button("保存") {
                    error = controller.save(rule)
                    if error == nil { dismiss() }
                }.buttonStyle(WorkButtonStyle(prominent: true)).workKeyboardFocus(radius: 0)
            }
        }.padding(26).frame(width: 650).background(WorkStyle.canvas).preferredColorScheme(.light).foregroundStyle(WorkStyle.ink)
            .font(.system(size: 12)).tint(WorkStyle.blue)
            .buttonStyle(WorkButtonStyle()).focusEffectDisabled().textFieldStyle(TerminalTextFieldStyle())
            .task(id: rule.conditions.map(\.kind)) { await refreshPreview() }
    }
    @ViewBuilder private func conditionInput(_ condition: Binding<TriggerCondition>) -> some View {
        let kind = condition.wrappedValue.kind
        let suggestions = preview.suggestions(for: kind)
        VStack(alignment: .leading, spacing: 8) {
            if kind == .appRunning || kind == .appFrontmost {
                HStack {
                    Button("选择应用…") { chooseApplication(condition) }.workKeyboardFocus(radius: 0)
                    if !suggestions.isEmpty { suggestionMenu(suggestions, condition: condition, title: "选择运行中的应用") }
                }
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: condition.wrappedValue.value) {
                    Text(FileManager.default.displayName(atPath: appURL.path)).foregroundStyle(WorkStyle.ink)
                }
                DisclosureGroup("应用标识（高级）") {
                    TextField("应用 Bundle ID", text: condition.value).padding(.top, 5)
                }
            } else {
                if !suggestions.isEmpty {
                    HStack {
                        suggestionMenu(suggestions, condition: condition, title: kind == .mountedVolume ? "选择已挂载磁盘" : kind == .processRunning ? "选择运行中的进程" : "选择当前观测")
                        Button("刷新") { Task { await refreshPreview() } }.workKeyboardFocus(radius: 0)
                    }
                } else if [.usbDevice, .bluetoothDevice, .audioOutput, .mountedVolume, .processRunning].contains(kind) {
                    HStack {
                        Text(preview.unavailable[kind] ?? "没有可选设备，连接后可刷新。").font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                        Button("刷新") { Task { await refreshPreview() } }.workKeyboardFocus(radius: 0)
                    }
                }
                TextField(kind.hint, text: condition.value)
            }
        }
    }
    private func scheduleInput(_ condition: Binding<TriggerCondition>) -> some View {
        let schedule = Binding<TriggerWeeklySchedule>(get: { condition.wrappedValue.schedule ?? TriggerWeeklySchedule() }, set: { condition.wrappedValue.schedule = $0 })
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                    let selected = schedule.wrappedValue.weekdays.contains(day)
                    Button {
                        if selected { schedule.wrappedValue.weekdays.remove(day) }
                        else { schedule.wrappedValue.weekdays.insert(day) }
                    } label: {
                        Text([1: "周日", 2: "周一", 3: "周二", 4: "周三", 5: "周四", 6: "周五", 7: "周六"][day]!)
                    }.buttonStyle(WorkButtonStyle(prominent: selected)).workKeyboardFocus(radius: 0)
                        .accessibilityValue(selected ? "已选择" : "未选择")
                }
            }
            WorkToggle(title: "全天", detail: "按所选星期从当地 00:00 到次日 00:00。", isOn: schedule.allDay)
            if !schedule.wrappedValue.allDay {
                HStack {
                    scheduleTimePicker("开始", minute: schedule.startMinute)
                    scheduleTimePicker("结束", minute: schedule.endMinute)
                }
            }
            WorkNote(text: "使用 Mac 当前时区的当地时间，开始包含、结束不包含。结束早于开始时跨至次日，归属开始的星期。夏令时跳过的时间不匹配，重复小时两次均按当地时间匹配。")
        }
    }
    private func scheduleTimePicker(_ label: String, minute: Binding<Int>) -> some View {
        // A weekly wall-clock time is not an absolute Date. Native NSDatePicker's
        // AX value can apply the system timezone even when its visual timezone
        // is UTC, so represent hours/minutes directly for both display and AX.
        let hour = Binding<Int>(get: { minute.wrappedValue / 60 }, set: { minute.wrappedValue = min(max($0, 0), 23) * 60 + minute.wrappedValue % 60 })
        let fraction = Binding<Int>(get: { minute.wrappedValue % 60 }, set: { minute.wrappedValue = (minute.wrappedValue / 60) * 60 + min(max($0, 0), 59) })
        return HStack(spacing: 5) {
            Text(label).font(WorkType.controlLabel)
            TextField("小时", value: hour, format: .number.precision(.integerLength(2))).frame(width: 46).accessibilityLabel(label + "小时，0 至 23")
            Text(":").foregroundStyle(WorkStyle.muted)
            TextField("分钟", value: fraction, format: .number.precision(.integerLength(2))).frame(width: 46).accessibilityLabel(label + "分钟，0 至 59")
        }.textFieldStyle(TerminalTextFieldStyle()).font(WorkType.body).monospacedDigit()
    }
    private func suggestionMenu(_ suggestions: [TriggerSuggestion], condition: Binding<TriggerCondition>, title: String) -> some View {
        TerminalActionMenu(title: title, titles: suggestions.map(\.title)) { index in
            if suggestions.indices.contains(index) { condition.wrappedValue.value = suggestions[index].value }
        }.frame(width: 250)
    }
    private func refreshPreview() async {
        let kinds = Set(rule.conditions.map(\.kind))
        let updated = await controller.preview(kinds: kinds)
        guard kinds == Set(rule.conditions.map(\.kind)) else { return }
        preview = updated
    }
    private func chooseApplication(_ condition: Binding<TriggerCondition>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "选择应用"; panel.message = "选择应用后自动保存它的标识，用于判断正在运行或位于前台。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let id = TriggerController.applicationBundleIdentifier(at: url) else { error = "所选应用没有有效的应用标识，请选择另一个应用。"; return }
        condition.wrappedValue.value = id
        error = nil
    }
}
