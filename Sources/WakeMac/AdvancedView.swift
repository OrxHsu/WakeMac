import SwiftUI
import AppKit

struct AdvancedView: View {
    @ObservedObject var appearance: AppearanceController
    @ObservedObject var notifier: LocalNotifier
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkCard(title: "菜单栏外观") {
                HStack { Text("图标").font(WorkType.controlLabel); Spacer(); Picker("菜单栏图标", selection: $appearance.icon) { ForEach(AppearanceController.Icon.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 160) }
                HStack { Text("PNG、JPEG、TIFF 或 ICNS").font(.system(size: 11)).foregroundStyle(WorkStyle.muted); Spacer(); Button("选择图标…", action: appearance.chooseIcon) }
                if appearance.icon == .custom { WorkToggle(title: "图标跟随系统明暗", detail: "关闭后保留原图颜色。", isOn: $appearance.template) }
                WorkToggle(title: "菜单栏显示结束时间", detail: "关闭时显示剩余时长。", isOn: $appearance.showEndTime)
                WorkToggle(title: "使用 24 小时制", isOn: $appearance.twentyFourHour)
                HStack { Text("图标两侧留白").font(WorkType.controlLabel); Spacer(); Text("\(Int(appearance.iconPadding)) pt").font(WorkType.body).monospacedDigit(); Stepper("图标两侧留白", value: $appearance.iconPadding, in: 0...12).labelsHidden() }
            }
            WorkCard(title: "通知声音", subtitle: appearance.soundName.isEmpty ? "使用系统默认声音" : "已使用自定义通知声音") {
                HStack { Button("选择声音…", action: appearance.chooseSound); Button("试听", action: appearance.previewSound); Spacer(); Button("恢复默认", action: appearance.resetSound) }
                WorkNote(text: "支持短于 30 秒的 AIFF、WAV 或 CAF；通知权限仍由系统管理。")
                WorkToggle(title: "通知时播放声音", isOn: $notifier.notificationSound)
                WorkToggle(title: "会话开始与结束播放声音", isOn: $notifier.lifecycleSound)
                WorkToggle(title: "延长会话时播放声音", isOn: $notifier.extensionSound)
            }
            WorkCard(title: "AppleScript") {
                Text("tell application \"WakeMac\"\n    start session mode \"desktop\" for minutes 30\n    session status\n    -- end session\nend tell")
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(WorkStyle.canvas, in: RoundedRectangle(cornerRadius: WorkStyle.inputRadius))
                WorkNote(text: "支持会话启停、延长、剩余时间、显示器与屏保、合盖、触发器和磁盘保活控制。background 需要已批准的合盖服务；所有命令采用偏好设置中的锁屏策略。")
                DisclosureGroup("更多脚本命令") {
                    Text("session is active\nsession time remaining\nextend session for minutes 15\nprevent display sleep\nallow display sleep\nprevent screen saver\nallow screen saver\nenable closed display mode\ndisable closed display mode\ntriggers are enabled\nenable triggers\ndisable triggers\nenable drive alive\ndisable drive alive")
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(.top, 8)
                }.font(WorkType.body)
            }
            if !appearance.message.isEmpty { WorkNote(text: appearance.message) }
        }
    }
}
