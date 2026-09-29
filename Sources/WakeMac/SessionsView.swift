import SwiftUI
import WakeMacCore

struct SessionsView: View {
    @ObservedObject var controller: SessionController
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkCard(title: "会话设置", subtitle: "选择何时结束；到点恢复正常休眠。") {
                HStack {
                    Text("结束条件").font(WorkType.controlLabel)
                    Spacer()
                    Picker("结束条件", selection: $controller.endCondition) {
                        ForEach(SessionEndCondition.allCases) { item in Text(item.title).tag(item) }
                    }.labelsHidden().frame(width: 190)
                }.disabled(controller.isActive || controller.isStarting)
                conditionFields.disabled(controller.isActive || controller.isStarting)
                HStack {
                    Text("开始时使用").font(WorkType.controlLabel)
                    Spacer()
                    Picker("会话工作模式", selection: $controller.defaultMode) {
                        Text("桌面工作").tag(WorkMode.desk)
                        Text("合盖后台工作").tag(WorkMode.background)
                    }.labelsHidden().frame(width: 190)
                }.disabled(controller.isActive || controller.isStarting)
                Text(controller.status).font(.system(size: 12)).foregroundStyle(WorkStyle.muted)
                    .accessibilityLabel("会话状态：" + controller.status)
                HStack {
                    Spacer()
                    Button(controller.isActive ? "结束会话" : "开始会话") {
                        Task {
                            if controller.isActive { await controller.end() }
                            else { await controller.start() }
                        }
                    }.buttonStyle(WorkButtonStyle(prominent: true)).disabled(controller.isStarting)
                }
            }
            WorkCard(title: "会话效果", subtitle: "手动、会话和自动触发的工作模式均适用；恢复正常休眠后停止。") {
                WorkToggle(title: "防止显示器闲时休眠", detail: "不会改变锁屏或密码设置；锁定后暂停。", isOn: $controller.preventDisplaySleep)
                effectText(controller.effectReport.display)
                Rectangle().fill(WorkStyle.line).frame(height: 1)
                WorkToggle(title: "防止闲时屏保", detail: "通过声明用户活动延后屏保，也会延后显示器休眠；锁定后暂停。", isOn: $controller.preventScreenSaver)
                effectText(controller.effectReport.screenSaver)
                Rectangle().fill(WorkStyle.line).frame(height: 1)
                WorkToggle(title: "轻微移动鼠标", detail: "每分钟移动 1 像素并移回，仅在已解锁时；每次打开应用默认关闭。", isOn: $controller.moveCursor)
                if controller.moveCursor {
                    HStack {
                        effectText(controller.effectReport.cursor)
                        Spacer()
                        Button("授权辅助功能") { controller.requestCursorAccess() }.buttonStyle(WorkButtonStyle())
                    }
                }
            }
            WorkCard(title: "磁盘保活", subtitle: "定期访问所选磁盘，减少闲置休眠；部分磁盘仍可能自行休眠。") {
                WorkToggle(title: "工作期间定期访问磁盘", detail: "仅作用于所选目录；不阻止手动弹出磁盘。", isOn: $controller.driveAlive)
                ForEach(controller.driveDirectories, id: \.path) { directory in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(directory.path).font(.system(size: 11)).lineLimit(2)
                            if let message = controller.effectReport.drives[directory.path] { effectText(message) }
                        }
                        Spacer()
                        Button { controller.driveDirectories.removeAll { $0 == directory } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain).accessibilityLabel("移除目录 " + directory.lastPathComponent)
                    }
                }
                Button("添加磁盘目录") { controller.chooseDriveDirectory() }.buttonStyle(WorkButtonStyle())
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
                    .textFieldStyle(.roundedBorder).accessibilityLabel("会话时长，分钟")
                Text("分钟").font(.system(size: 12)).foregroundStyle(WorkStyle.muted)
            }
        case .untilDate:
            HStack { Text("结束时间").font(WorkType.controlLabel); Spacer(); SchedulePicker(selection: $controller.endDate) }
        case .application:
            HStack {
                Text(controller.applicationURL?.deletingPathExtension().lastPathComponent ?? "未选择应用")
                    .font(.system(size: 12)).foregroundStyle(WorkStyle.muted)
                Spacer()
                Button("选择正在运行的应用") { controller.chooseApplication() }.buttonStyle(WorkButtonStyle())
            }
            WorkNote(text: "核验应用包身份及实际运行进程；全部匹配实例退出后结束。无法核验时继续等待。")
        case .download:
            HStack {
                Text(controller.downloadURL?.lastPathComponent ?? "未选择文件").font(.system(size: 12)).foregroundStyle(WorkStyle.muted).lineLimit(2)
                Spacer()
                Button("选择下载文件") { controller.chooseDownload() }.buttonStyle(WorkButtonStyle())
            }
            WorkNote(text: "先观察文件实际增长，再等待 30 秒稳定；临时下载后缀需重命名为完成文件。下载暂停也可能被视为稳定，重要下载请使用手动结束。")
        }
    }
    private func effectText(_ text: String) -> some View {
        Text(text).font(WorkType.caption).foregroundStyle(WorkStyle.muted).fixedSize(horizontal: false, vertical: true)
    }
}
