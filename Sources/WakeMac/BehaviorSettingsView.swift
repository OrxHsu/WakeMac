import SwiftUI

struct BehaviorSettingsView: View {
    @ObservedObject var behavior: BehaviorPreferences
    @State private var resetPrompt = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkCard(title: "默认会话", subtitle: "用于快捷启停、主动启用的启动与唤醒行为。") {
                WorkToggle(title: "默认无限期", isOn: $behavior.defaultIndefinite)
                if !behavior.defaultIndefinite { numberRow("默认时长", value: $behavior.defaultMinutes, range: 1...10080, suffix: "分钟") }
                WorkToggle(title: "应用启动后开始新会话", detail: "每次创建默认会话，不恢复旧任务或命令。", isOn: $behavior.startAtLaunch)
                WorkToggle(title: "系统唤醒后开始新会话", detail: "已有工作会话时不重复开始；保留立即锁屏保护。", isOn: $behavior.startAfterWake)
            }
            WorkCard(title: "运行提醒") {
                WorkToggle(title: "定期提醒会话仍在运行", isOn: $behavior.reminderEnabled)
                if behavior.reminderEnabled { numberRow("提醒间隔", value: $behavior.reminderMinutes, range: 1...10080, suffix: "分钟") }
                WorkToggle(title: "合盖工作提示音", detail: "合盖后播放；接电且连接外接屏时静音。", isOn: $behavior.lidToneEnabled)
                if behavior.lidToneEnabled {
                    WorkToggle(title: "重复提示音", isOn: $behavior.lidToneRepeat)
                    if behavior.lidToneRepeat { numberRow("声音间隔", value: $behavior.lidToneSeconds, range: 5...86400, suffix: "秒") }
                    HStack { Text("提示音音量").font(WorkType.controlLabel); Spacer(); Slider(value: $behavior.lidToneVolume, in: 0...1).frame(width: 150) }
                    WorkNote(text: "使用自定义通知声音或系统 Glass；只调整本应用声音，不改变系统音量。")
                }
            }
            WorkCard(title: "本机统计", subtitle: "仅记录 WakeMac 已核验的运行时长，不上传。") {
                WorkToggle(title: "记录工作统计", isOn: $behavior.statisticsEnabled)
                HStack {
                    Text("工作 \(Int(behavior.awakeSeconds / 60)) 分钟 · 合盖 \(Int(behavior.lidSeconds / 60)) 分钟 · \(behavior.activations) 次启动")
                        .font(WorkType.body).monospacedDigit().foregroundStyle(WorkStyle.muted)
                    Spacer(); Button("清零统计") { resetPrompt = true }
                }
            }
        }.confirmationDialog("清零本机工作统计？", isPresented: $resetPrompt) {
            Button("清零统计", role: .destructive) { behavior.resetStatistics() }
            Button("取消", role: .cancel) {}
        }
    }
    private func numberRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        HStack { Text(title).font(WorkType.controlLabel); Spacer(); Text(value.wrappedValue.formatted() + " " + suffix).font(WorkType.body).monospacedDigit(); Stepper(title, value: value, in: range).labelsHidden() }
    }
}
