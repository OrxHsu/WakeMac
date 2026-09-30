// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import SwiftUI

struct IdlePolicyView: View {
    @ObservedObject var controller: IdlePolicyController
    var immediateAuthentication = true
    var body: some View {
        WorkCard(title: "闲置后的屏幕", subtitle: "工作继续运行；屏保的密码要求跟随系统设置。") {
            WorkToggle(title: "闲置后熄屏锁定", detail: "此项需要 macOS 立即要求密码；其他策略下暂停。", isOn: $controller.lockEnabled).disabled(!immediateAuthentication)
            HStack { Text("锁定等待").font(WorkType.controlLabel); Spacer(); TerminalStepper(value: $controller.lockMinutes, in: 1...240) { Text("\(Int(controller.lockMinutes)) 分钟").monospacedDigit() }.fixedSize().accessibilityLabel("闲置锁定等待时间") }
            Rectangle().fill(WorkStyle.line).frame(height: 1)
            WorkToggle(title: "闲置后启动系统屏保", detail: "启用“防止闲时屏保”时此项暂停。", isOn: $controller.screenSaverEnabled)
            HStack { Text("屏保等待").font(WorkType.controlLabel); Spacer(); TerminalStepper(value: $controller.screenSaverMinutes, in: 1...240) { Text("\(Int(controller.screenSaverMinutes)) 分钟").monospacedDigit() }.fixedSize().accessibilityLabel("屏保等待时间") }
            WorkNote(text: controller.status)
        }
    }
}
