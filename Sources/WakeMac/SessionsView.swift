// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import SwiftUI
import WakeMacCore

struct SessionsView: View {
    @ObservedObject var controller: SessionController
    @State private var extensionMinutes: Double = 15
    @State private var processSearch = ""
    private var displayedProcesses: [DiscoveredProcess] {
        let search = processSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return controller.processChoices.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.executablePath.localizedCaseInsensitiveContains(search) || String($0.identity.pid).contains(search) }
    }
    private var displayPrevention: Binding<Bool> {
        Binding(get: { controller.effectivePreventDisplaySleep }, set: { value in
            if controller.workingProvider?() == true { controller.setDisplayPrevention(value) }
            else { controller.preventDisplaySleep = value }
        })
    }
    private var saverPrevention: Binding<Bool> {
        Binding(get: { controller.effectivePreventScreenSaver }, set: { value in
            if controller.workingProvider?() == true { controller.setScreenSaverPrevention(value) }
            else { controller.preventScreenSaver = value }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkCard(title: "会话设置", subtitle: "选择何时结束；到点恢复正常休眠。") {
                HStack {
                    Text("结束条件").font(WorkType.controlLabel)
                    Spacer()
                    TerminalPicker("结束条件", selection: $controller.endCondition, choices: SessionEndCondition.allCases.map { TerminalChoice($0.title, $0) }).labelsHidden().frame(width: 190)
                }.disabled(controller.isActive || controller.isStarting)
                conditionFields.disabled(controller.isActive || controller.isStarting)
                HStack {
                    Text("开始时使用").font(WorkType.controlLabel)
                    Spacer()
                    TerminalPicker("会话工作模式", selection: $controller.defaultMode, choices: [TerminalChoice("桌面工作", .desk), TerminalChoice("合盖后台工作", .background)]).labelsHidden().frame(width: 190)
                }.disabled(controller.isActive || controller.isStarting)
                Text(controller.status).font(.system(size: 12)).foregroundStyle(WorkStyle.muted)
                    .accessibilityLabel("会话状态：" + controller.status)
                if controller.isActive, let deadline = controller.deadline {
                    HStack {
                        Text("结束：" + deadline.formatted(date: .abbreviated, time: .shortened)).font(WorkType.caption).foregroundStyle(WorkStyle.muted)
                        Spacer()
                        TextField("分钟", value: $extensionMinutes, format: .number).textFieldStyle(TerminalTextFieldStyle()).frame(width: 65).accessibilityLabel("延长会话的分钟数")
                        Button("延长会话") { controller.extend(minutes: extensionMinutes) }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                    }
                }
                HStack {
                    Spacer()
                    Button(controller.isActive ? "结束会话" : "开始会话") {
                        Task {
                            if controller.isActive { await controller.end() }
                            else { await controller.start() }
                        }
                    }.buttonStyle(WorkButtonStyle(prominent: true)).workKeyboardFocus(radius: 0).disabled(controller.isStarting)
                }
            }
            WorkCard(title: "会话效果", subtitle: "手动、会话和自动触发的工作模式均适用；恢复正常休眠后停止。") {
                WorkToggle(title: "防止显示器闲时休眠", detail: "不会改变锁屏或密码设置；锁定后暂停。", isOn: displayPrevention)
                effectText(controller.effectReport.display)
                Rectangle().fill(WorkStyle.line).frame(height: 1)
                WorkToggle(title: "防止闲时屏保", detail: "通过声明用户活动延后屏保，也会延后显示器休眠；锁定后暂停。", isOn: saverPrevention)
                effectText(controller.effectReport.screenSaver)
                ForEach(controller.screenSaverExceptionBundleIDs, id: \.self) { identifier in
                    HStack {
                        Text("屏保例外：" + controller.screenSaverExceptionName(identifier)).font(WorkType.caption)
                        Spacer()
                        Button { controller.screenSaverExceptionBundleIDs.removeAll { $0 == identifier } } label: { TerminalIcon(name: "minus.circle") }
                            .buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0).accessibilityLabel("移除屏保例外 " + controller.screenSaverExceptionName(identifier))
                    }
                }
                Button("添加屏保例外应用") { controller.chooseScreenSaverException() }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                WorkNote(text: "例外应用运行时暂停自动启动屏保；工作中的开关修改仅影响本次，正常模式下保存为默认。")
                Rectangle().fill(WorkStyle.line).frame(height: 1)
                WorkToggle(title: "轻微移动鼠标", detail: "按所设间隔移动 1 像素并移回，仅在已解锁时。保留系统闲置计时；显示器和屏保由各自开关控制。", isOn: $controller.moveCursor)
                if controller.moveCursor {
                    secondsField("移动间隔", value: $controller.mouseMovementIntervalSeconds)
                    WorkToggle(title: "仅在闲置时移动", detail: "没有键盘或鼠标输入达到所设时长后才移动；屏保运行时暂停。", isOn: $controller.mouseOnlyWhenIdle)
                    if controller.mouseOnlyWhenIdle { secondsField("闲置多久后开始移动", value: $controller.mouseIdleThresholdSeconds) }
                    WorkToggle(title: "长期闲置后停止移动", detail: "达到停止时长后暂停；再次使用电脑会重新计时。", isOn: Binding(get: { controller.mouseStopAfterIdleSeconds != nil }, set: { controller.mouseStopAfterIdleSeconds = $0 ? 3600 : nil }))
                    if controller.mouseStopAfterIdleSeconds != nil {
                        secondsField("闲置多久后停止移动", value: Binding(get: { controller.mouseStopAfterIdleSeconds ?? 3600 }, set: { controller.mouseStopAfterIdleSeconds = $0 }))
                    }
                    HStack {
                        effectText(controller.effectReport.cursor)
                        Spacer()
                        Button("授权辅助功能") { controller.requestCursorAccess() }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                    }
                }
            }
            WorkCard(title: "磁盘保活", subtitle: "定期访问所选磁盘，减少闲置休眠；部分磁盘仍可能自行休眠。") {
                WorkToggle(title: "工作期间定期访问磁盘", detail: "仅作用于所选目录；不阻止手动弹出磁盘。", isOn: $controller.driveAlive)
                if controller.driveAlive { secondsField("磁盘访问间隔", value: $controller.diskAccessIntervalSeconds) }
                ForEach(controller.driveDirectories, id: \.path) { directory in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(directory.path).font(.system(size: 11)).lineLimit(2)
                            if let message = controller.effectReport.drives[directory.path] { effectText(message) }
                        }
                        Spacer()
                        Button { controller.driveDirectories.removeAll { $0 == directory } } label: { TerminalIcon(name: "minus.circle") }
                            .buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0).accessibilityLabel("移除目录 " + directory.lastPathComponent)
                    }
                }
                Button("添加磁盘目录") { controller.chooseDriveDirectory() }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
            }
        }
    }
    @ViewBuilder private var conditionFields: some View {
        switch controller.endCondition {
        case .indefinite:
            WorkNote(text: "保持工作状态，直到你结束会话或手动切换模式。")
        case .duration:
            HStack {
                Text("持续时长").font(WorkType.controlLabel)
                Spacer()
                TextField("分钟", value: $controller.durationMinutes, format: .number).frame(width: 75)
                    .textFieldStyle(TerminalTextFieldStyle()).accessibilityLabel("会话时长，分钟")
                Text("分钟").font(.system(size: 12)).foregroundStyle(WorkStyle.muted)
            }
        case .untilDate:
            HStack { Text("结束时间").font(WorkType.controlLabel); Spacer(); SchedulePicker(selection: $controller.endDate) }
        case .application:
            HStack {
                Text(controller.applicationURL?.deletingPathExtension().lastPathComponent ?? "未选择应用")
                    .font(.system(size: 12)).foregroundStyle(WorkStyle.muted)
                Spacer()
                Button("选择正在运行的应用") { controller.chooseApplication() }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
            }
            WorkNote(text: "核验应用包身份及实际运行进程；全部匹配实例退出后结束。无法核验时继续等待。")
        case .process:
            if !controller.processChoices.isEmpty {
                TextField("搜索进程名称、路径或 PID", text: $processSearch).textFieldStyle(TerminalTextFieldStyle()).font(WorkType.body)
            }
            HStack {
                TerminalActionMenu(title: controller.selectedProcess.map { "\($0.name) · PID \($0.identity.pid)" } ?? "选择进程", titles: displayedProcesses.map { "\($0.name) · PID \($0.identity.pid)" }) { index in
                    if displayedProcesses.indices.contains(index) { controller.selectedProcess = displayedProcesses[index] }
                }.frame(width: 260).disabled(displayedProcesses.isEmpty)
                Spacer()
                Button("刷新进程") { controller.refreshProcesses() }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
            }
            if let process = controller.selectedProcess { effectText(process.executablePath) }
            WorkNote(text: controller.processDiscoveryStatus + "。仅监测所选的这次运行；同名进程重启不会延续会话。")
        case .download:
            HStack {
                Text(controller.downloadURL?.lastPathComponent ?? "未选择文件").font(.system(size: 12)).foregroundStyle(WorkStyle.muted).lineLimit(2)
                Spacer()
                Button("选择下载文件") { controller.chooseDownload() }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
            }
            if let percent = controller.downloadProgressPercent {
                ProgressView(value: percent, total: 100)
                effectText("系统报告下载进度：" + percent.formatted(.number.precision(.fractionLength(0))) + "%")
            } else { effectText("未获得系统发布的下载百分比；仍按文件增长与稳定时长监测。") }
            secondsField("下载稳定时长", value: $controller.downloadStabilitySeconds)
            WorkNote(text: "用于大文件下载：下载期间保持唤醒，完成后结束本次会话并恢复正常休眠。先观察文件增长，再等待完成重命名和稳定；网络暂停可能被视为稳定，重要下载请手动结束。")
        }
    }
    private func secondsField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).font(WorkType.controlLabel)
            Spacer()
            TextField("秒", value: value, format: .number).textFieldStyle(TerminalTextFieldStyle()).frame(width: 75).accessibilityLabel(title + "，秒")
            Text("秒").font(WorkType.caption).foregroundStyle(WorkStyle.muted)
        }
    }
    private func effectText(_ text: String) -> some View {
        Text(text).font(WorkType.caption).foregroundStyle(WorkStyle.muted).fixedSize(horizontal: false, vertical: true)
    }
}
