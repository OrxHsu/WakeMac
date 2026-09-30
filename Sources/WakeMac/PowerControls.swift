// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import SwiftUI
import ServiceManagement

/// Both surfaces show the backend's observed state, rather than optimistic switch values.
struct PowerControls: View {
    @ObservedObject var model: AppModel
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            control("保持唤醒", detail: "阻止闲置休眠，屏幕仍可自动关闭", icon: "sun.max", enabled: model.keepsAwake) { enabled in
                Task { await model.setKeepsAwake(enabled) }
            }
            Rectangle().fill(WorkStyle.line.opacity(0.6)).frame(height: 1)
            control("合盖继续运行", detail: "开启时同时保持唤醒", icon: "laptopcomputer", enabled: model.runsWithLidClosed) { enabled in
                Task { await model.changeSessionLidMode(enabled) }
            }.disabled(model.helperStatus != .enabled)
            HStack(spacing: 10) {
                TerminalIcon(name: model.helperStatus == .enabled ? "checkmark.shield" : "key")
                    .frame(width: 22)
                Text(serviceSummary)
                Spacer(minLength: 0)
                if model.helperStatus != .enabled {
                    Button(model.helperStatus == .requiresApproval ? "完成授权…" : "启用服务…", action: model.enableHelper)
                        .buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0).foregroundStyle(WorkStyle.blue).disabled(model.busy)
                }
            }.font(compact ? WorkType.compactCaption : WorkType.caption).foregroundStyle(WorkStyle.muted)
            if model.helperStatus != .enabled && !model.helperMessage.isEmpty {
                Text(model.helperMessage).font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.toggleStyle(TerminalSwitchStyle()).controlSize(.small)
    }

    private func control(_ title: String, detail: String, icon: String, enabled: Bool, action: @escaping (Bool) -> Void) -> some View {
        WorkToggle(title: title, detail: model.snapshot == nil ? "等待状态核验" : detail, icon: icon, compact: compact,
                   isOn: Binding(get: { enabled }, set: action))
            .disabled(model.busy || model.snapshot == nil || model.pending != nil)
    }

    private var serviceSummary: String {
        switch model.helperStatus {
        case .enabled: "合盖服务已授权"
        case .requiresApproval: "合盖服务等待批准"
        default: "合盖运行需要一次授权"
        }
    }
}
