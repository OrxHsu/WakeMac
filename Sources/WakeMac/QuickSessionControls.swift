import SwiftUI

struct QuickSessionControls: View {
    @ObservedObject var model: AppModel
    @ObservedObject var sessions: SessionController
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack {
                Text("会话").font(WorkType.controlLabel)
                Spacer()
                Button(model.verifiedWork ? "结束" : "开始默认会话") { Task { await model.performShortcut(4) } }
                    .disabled(model.busy || sessions.isStarting)
            }
            WorkToggle(title: "阻止显示器休眠", compact: compact, isOn: Binding(get: { sessions.effectivePreventDisplaySleep }, set: { value in Task { await model.changeDisplayPrevention(value) } }))
            WorkToggle(title: "阻止闲时屏保", compact: compact, isOn: Binding(get: { sessions.effectivePreventScreenSaver }, set: { value in Task { await model.changeScreenSaverPrevention(value) } }))
            if sessions.deadline != nil {
                HStack {
                    Text("延长会话").font(compact ? WorkType.compactLabel : WorkType.controlLabel)
                    Spacer()
                    Button("+15 分钟") { _ = sessions.extend(minutes: 15); model.onUpdate?() }.disabled(!model.verifiedWork)
                }
            }
        }.font(WorkType.body).buttonStyle(WorkButtonStyle()).disabled(model.busy)
    }
}
