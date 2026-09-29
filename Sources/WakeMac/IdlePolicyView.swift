import SwiftUI

struct IdlePolicyView: View {
    @ObservedObject var controller: IdlePolicyController
    var body: some View {
        WorkCard(title: "闲置后的屏幕", subtitle: "工作继续运行；屏幕关闭或屏保启动后仍立即要求密码。") {
            WorkToggle(title: "闲置后熄屏锁定", isOn: $controller.lockEnabled)
            HStack { Text("锁定等待").font(WorkType.controlLabel); Spacer(); Stepper(value: $controller.lockMinutes, in: 1...240) { Text("\(Int(controller.lockMinutes)) 分钟").monospacedDigit() }.fixedSize().accessibilityLabel("闲置锁定等待时间") }
            Rectangle().fill(WorkStyle.line).frame(height: 1)
            WorkToggle(title: "闲置后启动系统屏保", detail: "启用“防止闲时屏保”时此项暂停。", isOn: $controller.screenSaverEnabled)
            HStack { Text("屏保等待").font(WorkType.controlLabel); Spacer(); Stepper(value: $controller.screenSaverMinutes, in: 1...240) { Text("\(Int(controller.screenSaverMinutes)) 分钟").monospacedDigit() }.fixedSize().accessibilityLabel("屏保等待时间") }
            WorkNote(text: controller.status)
        }
    }
}
