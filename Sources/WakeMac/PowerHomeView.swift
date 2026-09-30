import AppKit
import ServiceManagement
import SwiftUI
import WakeMacCore

struct PowerHomeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var sessions: SessionController
    var openSessions: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection

    private var controlsDisabled: Bool { model.busy || model.snapshot == nil || model.pending != nil }
    private var working: Bool { model.active == .background || model.active == .desk || model.keepsAwake || model.runsWithLidClosed }
    private var statusColor: Color { model.error ? TerminalStyle.warning : model.verifiedWork ? TerminalStyle.accent : TerminalStyle.amber }
    private var status: String {
        if model.busy { return "正在切换" }
        if model.pending != nil { return "等待设置" }
        if model.error { return "需要处理" }
        if model.snapshot == nil || model.active == nil { return "等待核验" }
        return model.verifiedWork ? "正在运行" : "允许休眠"
    }
    private var detail: String {
        if model.busy || model.error || model.pending != nil { return model.headline }
        switch model.active {
        case .background: return "保持唤醒 · 合盖继续"
        case .desk: return "保持唤醒 · 允许合盖休眠"
        case .normal: return "工作已收尾 · 恢复自然休眠"
        case nil: return "读取系统状态后即可开始"
        }
    }
    private var endSummary: String {
        if let countdown = model.countdownText { return countdown }
        if sessions.isActive { return sessions.status }
        if model.triggerOwnedMode != nil { return model.triggerSummary }
        return working ? "手动结束" : "尚未开始"
    }

    var body: some View {
        VStack(spacing: 12) {
            hero
            modes
            controls
            if model.pending != nil || model.error {
                VStack(alignment: .leading, spacing: 10) {
                    WorkNote(text: model.message, icon: "exclamationmark.circle")
                    HStack {
                        if model.pending != nil { Button("打开锁屏设置", action: model.openLockSettings).workKeyboardFocus(radius: 0) }
                        Button("重新检查") { model.error = false; Task { await model.refresh() } }.workKeyboardFocus(radius: 0)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).terminalSurface()
            }
        }.buttonStyle(TerminalButtonStyle()).focusEffectDisabled()
    }

    private var hero: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SESSION STATUS").font(TerminalStyle.mono(11)).tracking(1)
                        Text(model.active?.title ?? "等待核验")
                            .font(TerminalStyle.display(geometry.size.width < 620 ? 44 : 54))
                            .lineLimit(1).minimumScaleFactor(0.75).contentTransition(.opacity)
                            .accessibilityAddTraits(.isHeader)
                        HStack(spacing: 9) {
                            Rectangle().fill(statusColor).frame(width: 8, height: 8)
                            Text(status).font(.system(size: 17, weight: .semibold))
                            if model.busy { ProgressView().controlSize(.small) }
                        }.padding(.horizontal, 12).padding(.vertical, 7)
                            .background(statusColor.opacity(0.08))
                        Text(detail).font(.system(size: 14)).foregroundStyle(TerminalStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(width: geometry.size.width * 0.51, alignment: .leading)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: status)
                    if let url = Bundle.main.url(forResource: "PowerTerminal", withExtension: "png"), let image = NSImage(contentsOf: url) {
                        Image(nsImage: image).resizable().scaledToFit()
                            .padding(.leading, 4).accessibilityHidden(true)
                    }
                }.padding(.horizontal, 24).padding(.vertical, 20)
            }.frame(height: 228).background(TerminalGrid())
            HStack(spacing: 14) {
                Text("结束条件").font(.system(size: 12, weight: .semibold))
                Rectangle().fill(TerminalStyle.line).frame(width: 1, height: 21)
                Text(endSummary).font(.system(size: 12)).foregroundStyle(TerminalStyle.muted)
                    .lineLimit(1).help(endSummary)
                Spacer(minLength: 0)
                Button(action: openSessions) {
                    TerminalLabel("设置结束条件", systemImage: "arrow.right")
                        .labelStyle(.titleAndIcon).font(.system(size: 12))
                }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0).fixedSize()
                Button(working ? "结束工作" : "开始工作") {
                    model.quitWhenReady = false
                    Task {
                        if working { await model.choose(.normal) }
                        else { await model.beginDefaultSession() }
                    }
                }.buttonStyle(TerminalButtonStyle(prominent: true)).workKeyboardFocus(radius: 0)
                    .disabled(model.busy || sessions.isStarting)
            }.padding(10).padding(.leading, 8)
                .overlay(Rectangle().stroke(TerminalStyle.line.opacity(0.75)))
                .padding(8)
        }.terminalSurface(cut: 18)
    }

    private var modes: some View {
        HStack(spacing: 0) {
            ForEach(WorkMode.allCases, id: \.self) { mode in
                Button {
                    model.quitWhenReady = false
                    Task { await model.choose(mode) }
                } label: {
                    HStack(spacing: 9) {
                        TerminalIcon(name: model.active == mode ? "square.fill" : mode == .background ? "laptopcomputer" : mode == .desk ? "display" : "moon.zzz")
                            .font(.system(size: model.active == mode ? 9 : 18)).frame(width: 22)
                        Text(mode.title).font(.system(size: 15, weight: .semibold))
                    }.frame(maxWidth: .infinity).frame(height: 48)
                        .background {
                            if model.active == mode {
                                TerminalStyle.selection.matchedGeometryEffect(id: "mode", in: selection)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if model.active == mode { Rectangle().fill(TerminalStyle.accent).frame(width: 60, height: 2) }
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
                    .disabled(model.busy || (mode == .background && model.helperStatus != .enabled))
                    .accessibilityAddTraits(model.active == mode ? [.isSelected] : [])
                if mode != WorkMode.allCases.last { Rectangle().fill(TerminalStyle.line).frame(width: 1) }
            }
        }.frame(height: 48).terminalSurface()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.active)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            TerminalPowerToggle(title: "保持唤醒", detail: "阻止闲置休眠，屏幕仍可自动关闭", icon: "sun.max", isOn: Binding(
                get: { model.keepsAwake }, set: { value in Task { await model.setKeepsAwake(value) } }))
                .disabled(controlsDisabled).padding(.vertical, 13)
            rule
            TerminalPowerToggle(title: "合盖继续运行", detail: "开启时同时保持唤醒", icon: "laptopcomputer", isOn: Binding(
                get: { model.runsWithLidClosed }, set: { value in Task { await model.changeSessionLidMode(value) } }))
                .disabled(controlsDisabled || model.helperStatus != .enabled).padding(.vertical, 13)
            rule
            HStack(spacing: 10) {
                TerminalIcon(name: "display").font(.system(size: 18)).frame(width: 22)
                Text("允许屏幕自动关闭").font(.system(size: 13))
                Spacer()
                Toggle("允许屏幕自动关闭", isOn: Binding(
                    get: { !sessions.effectivePreventDisplaySleep },
                    set: { allowed in Task { await model.changeDisplayPrevention(!allowed) } }))
                    .labelsHidden().toggleStyle(TerminalSwitchStyle())
                    .disabled(model.busy || sessions.isStarting)
            }.padding(.vertical, 13)
            rule
            HStack(spacing: 8) {
                TerminalIcon(name: model.helperStatus == .enabled ? "square.fill" : "key")
                    .font(.system(size: 9))
                if model.helperStatus == .enabled {
                    Text("合盖服务已授权").font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
                } else {
                    Button(model.helperStatus == .requiresApproval ? "完成合盖服务授权…" : "启用合盖服务…", action: model.enableHelper)
                        .buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0).font(.system(size: 12)).disabled(model.busy)
                }
                Spacer()
                if sessions.deadline != nil {
                    Button("+15 分钟") { _ = sessions.extend(minutes: 15); model.onUpdate?() }.workKeyboardFocus(radius: 0)
                        .disabled(!model.verifiedWork)
                }
                Button("立即休眠") { Task { await model.choose(.normal, sleep: true) } }.workKeyboardFocus(radius: 0).disabled(model.busy)
            }.padding(.vertical, 10)
            if model.helperStatus != .enabled && !model.helperMessage.isEmpty {
                Text(model.helperMessage).font(WorkType.caption).foregroundStyle(TerminalStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
            }
        }.padding(.horizontal, 18).terminalSurface()
    }
    private var rule: some View { Rectangle().fill(TerminalStyle.line.opacity(0.45)).frame(height: 1) }
}

private struct TerminalPowerToggle: View {
    let title: String
    let detail: String
    let icon: String
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 10) {
            TerminalIcon(name: icon).font(.system(size: 18)).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(TerminalSwitchStyle())
                .accessibilityHint(detail)
        }
    }
}
