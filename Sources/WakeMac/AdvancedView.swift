import SwiftUI
import AppKit

struct AdvancedView: View {
    @ObservedObject var appearance: AppearanceController
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkCard(title: "菜单栏外观") {
                HStack { Text("图标"); Spacer(); Picker("菜单栏图标", selection: $appearance.icon) { ForEach(AppearanceController.Icon.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 160) }
                HStack { Text("PNG、JPEG、TIFF 或 ICNS").font(.system(size: 11)).foregroundStyle(WorkStyle.muted); Spacer(); Button("选择图标…", action: appearance.chooseIcon) }
                if appearance.icon == .custom { WorkToggle(title: "图标跟随系统明暗", detail: "关闭后保留原图颜色。", isOn: $appearance.template) }
                WorkToggle(title: "菜单栏显示结束时间", detail: "关闭时显示剩余时长。", isOn: $appearance.showEndTime)
                WorkToggle(title: "使用 24 小时制", isOn: $appearance.twentyFourHour)
            }
            WorkCard(title: "通知声音", subtitle: appearance.soundName.isEmpty ? "使用系统默认声音" : "已使用自定义通知声音") {
                HStack { Button("选择声音…", action: appearance.chooseSound); Button("试听", action: appearance.previewSound); Spacer(); Button("恢复默认", action: appearance.resetSound) }
                WorkNote(text: "支持短于 30 秒的 AIFF、WAV 或 CAF；通知权限仍由系统管理。")
            }
            WorkCard(title: "AppleScript") {
                Text("tell application \"WakeMac\"\n    start session mode \"desktop\" for minutes 30\n    session status\n    -- end session\nend tell")
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(WorkStyle.canvas, in: RoundedRectangle(cornerRadius: WorkStyle.inputRadius))
                WorkNote(text: "background 开启合盖会话，需要已批准的合盖服务。脚本命令同样先核验锁屏保护。")
            }
            if !appearance.message.isEmpty { WorkNote(text: appearance.message) }
        }
    }
}
