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
                Task { await model.setRunsWithLidClosed(enabled) }
            }.disabled(model.helperStatus != .enabled)
            HStack(spacing: 6) {
                Image(systemName: model.helperStatus == .enabled ? "checkmark.shield" : "key")
                Text(serviceSummary)
                Spacer(minLength: 0)
                if model.helperStatus != .enabled {
                    Button(model.helperStatus == .requiresApproval ? "完成授权…" : "启用服务…", action: model.enableHelper)
                        .buttonStyle(.plain).foregroundStyle(WorkStyle.blue).disabled(model.busy)
                }
            }.font(compact ? WorkType.compactCaption : WorkType.caption).foregroundStyle(WorkStyle.muted)
            if model.helperStatus != .enabled && !model.helperMessage.isEmpty {
                Text(model.helperMessage).font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.toggleStyle(.switch).controlSize(.small)
    }

    private func control(_ title: String, detail: String, icon: String, enabled: Bool, action: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { enabled }, set: action)) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: compact ? 15 : 18))
                    .foregroundStyle(enabled ? WorkStyle.blue : WorkStyle.muted).frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(compact ? WorkType.compactLabel : WorkType.controlLabel)
                    Text(model.snapshot == nil ? "等待状态核验" : detail)
                        .font(compact ? WorkType.compactCaption : WorkType.caption).foregroundStyle(WorkStyle.muted)
                }
                Spacer(minLength: 8)
            }
        }.accessibilityLabel(title).accessibilityHint(detail)
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
