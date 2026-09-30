// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import SwiftUI
import AppKit
import WakeMacCore

enum MenuMark {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            let moon = NSBezierPath()
            moon.move(to: NSPoint(x: 10.5, y: 17))
            moon.curve(to: NSPoint(x: 2.3, y: 7.5), controlPoint1: NSPoint(x: 5.7, y: 15.8), controlPoint2: NSPoint(x: 1.8, y: 12.2))
            moon.curve(to: NSPoint(x: 10.5, y: 1.5), controlPoint1: NSPoint(x: 2.7, y: 3.5), controlPoint2: NSPoint(x: 6.5, y: 1.0))
            moon.curve(to: NSPoint(x: 18, y: 6.8), controlPoint1: NSPoint(x: 14.2, y: 1.8), controlPoint2: NSPoint(x: 16.7, y: 4.0))
            moon.curve(to: NSPoint(x: 10.5, y: 17), controlPoint1: NSPoint(x: 10.6, y: 5.7), controlPoint2: NSPoint(x: 7.9, y: 10.0))
            moon.close(); moon.fill()
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState(); context.setBlendMode(.clear)
                context.setLineWidth(0.55)
                context.move(to: CGPoint(x: 10.0, y: 16.1))
                context.addCurve(to: CGPoint(x: 13.3, y: 2.2), control1: CGPoint(x: 6.6, y: 10.8), control2: CGPoint(x: 8.1, y: 3.9))
                context.strokePath(); context.restoreGState()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "WakeMac"
        return image
    }
}

struct ControlPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var sessions: SessionController
    var standalone = false
    var height: CGFloat = 560
    var closePopover: (() -> Void)?
    @State private var expanded = false
    @Namespace private var modeSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel, standalone: Bool = false, height: CGFloat = 560, closePopover: (() -> Void)? = nil) {
        self.model = model; self.sessions = model.sessions
        self.standalone = standalone; self.height = height; self.closePopover = closePopover
    }

    private var protected: Bool { model.snapshot?.lockPolicy == .immediate }
    private var statusColor: Color {
        model.error || model.pending != nil ? TerminalStyle.warning : model.verifiedWork ? TerminalStyle.accent : TerminalStyle.amber
    }
    private var title: String {
        model.busy ? "正在切换" : model.pending != nil ? "等待确认" : model.error ? "需要检查" : model.active?.title ?? "读取状态"
    }
    private var sessionSummary: String {
        if let countdown = model.countdownText { return countdown }
        if sessions.isActive { return sessions.status }
        if model.triggerOwnedMode != nil { return model.triggerSummary }
        return model.verifiedWork ? "手动结束" : "尚未开始会话"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            rule
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    status
                    modes
                    PowerControls(model: model, compact: true)
                        .padding(12).background(.white)
                        .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.6)))
                    quickActions
                    if let countdown = model.countdownText {
                        HStack(spacing: 8) {
                            TerminalIcon(name: "timer", size: 14)
                            Text(countdown).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button("取消", action: model.cancelVisibleCountdown)
                                .buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
                        }.font(.system(size: 11)).foregroundStyle(TerminalStyle.accent)
                            .padding(10).background(TerminalStyle.selection)
                    }
                    if model.pending != nil || model.error { feedback }
                }.padding(16).terminalReveal()
            }.frame(maxWidth: .infinity)
            rule
            footer
        }.frame(width: 360, height: height)
            .background(TerminalStyle.paper)
            .foregroundStyle(TerminalStyle.ink).tint(TerminalStyle.accent)
            .buttonStyle(WorkButtonStyle()).focusEffectDisabled().preferredColorScheme(.light)
            .onExitCommand { if !standalone { closePopover?() } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WakeMac").font(.system(size: 20, weight: .semibold))
                Text("快捷控制").font(.system(size: 10)).foregroundStyle(TerminalStyle.muted)
            }
            Spacer()
            if let battery = model.battery {
                TerminalLabel("\(battery.percent)%", systemImage: battery.onBattery ? "battery.75percent" : "battery.100percent.bolt")
                    .font(TerminalStyle.mono(11)).foregroundStyle(TerminalStyle.muted)
            }
            Button { model.openPreferences?() } label: {
                TerminalIcon(name: "arrow.right", size: 16).frame(width: 30, height: 32)
                    .background(.white).overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.6)))
            }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
                .accessibilityLabel("打开主窗口").help("打开 WakeMac 主窗口")
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(title).font(.system(size: 28, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8).contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if model.busy { ProgressView().controlSize(.small) }
                else { Rectangle().fill(statusColor).frame(width: 8, height: 8).accessibilityHidden(true) }
            }
            Text(model.headline).font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                TerminalIcon(name: "timer", size: 12)
                Text(sessionSummary).font(.system(size: 11)).lineLimit(2)
            }.foregroundStyle(model.verifiedWork ? TerminalStyle.accent : TerminalStyle.muted)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(TerminalGrid())
            .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.6)))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: title)
    }

    private var modes: some View {
        HStack(spacing: 0) {
            ForEach(WorkMode.allCases, id: \.self) { mode in
                modeButton(mode)
                if mode != WorkMode.allCases.last { Rectangle().fill(TerminalStyle.line.opacity(0.6)).frame(width: 1) }
            }
        }.frame(height: 58).background(.white)
            .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.6)))
            .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: model.active)
    }

    private func modeButton(_ mode: WorkMode) -> some View {
        let selected = model.active == mode && model.pending == nil && !model.error
        return Button {
            model.quitWhenReady = false
            Task { await model.choose(mode) }
        } label: {
            VStack(spacing: 5) {
                TerminalIcon(name: mode == .background ? "laptopcomputer" : mode == .desk ? "display" : "moon.zzz", size: 16)
                Text(mode.title).font(.system(size: 12, weight: .medium))
            }.frame(maxWidth: .infinity).frame(height: 58)
                .foregroundStyle(selected ? TerminalStyle.accent : TerminalStyle.ink)
                .background {
                    if selected { TerminalStyle.selection.matchedGeometryEffect(id: "quick-mode", in: modeSelection) }
                }
                .overlay(alignment: .bottom) {
                    if selected { Rectangle().fill(TerminalStyle.accent).frame(width: 32, height: 2) }
                }.contentShape(Rectangle())
        }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
            .disabled(model.busy || (mode == .background && model.helperStatus != .enabled))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var quickActions: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack {
                    Text("会话快捷操作").font(.system(size: 12, weight: .medium))
                    Spacer()
                    TerminalIcon(name: expanded ? "chevron.up" : "chevron.down", size: 12)
                }.padding(.vertical, 8).contentShape(Rectangle())
            }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
                .accessibilityValue(expanded ? "已展开" : "已收起")
            if expanded {
                QuickSessionControls(model: model, sessions: sessions, compact: true)
                    .padding(.top, 10).padding(.bottom, 4)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -4)))
            }
        }.padding(.horizontal, 2)
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkNote(text: model.message, icon: "exclamationmark.circle")
            HStack {
                if model.pending != nil {
                    Button("打开系统设置", action: model.openLockSettings).workKeyboardFocus(radius: 0)
                }
                Button("重新检查") { model.error = false; Task { await model.refresh() } }.workKeyboardFocus(radius: 0)
            }
        }.padding(12).background(.white)
            .overlay(Rectangle().strokeBorder(TerminalStyle.warning.opacity(0.5)))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TerminalIcon(name: protected ? "lock.shield" : "lock.trianglebadge.exclamationmark", size: 12)
                    .frame(width: 22)
                Text(model.lockSummary).font(.system(size: 10))
                Spacer(minLength: 0)
                if model.display.sessionLocked == true { Text("已锁定").font(.system(size: 10)) }
            }.foregroundStyle(TerminalStyle.muted)
            HStack {
                HStack(spacing: 10) {
                    TerminalIcon(name: "laptopcomputer", size: 16).frame(width: 22)
                    Text(displaySummary)
                }.font(.system(size: 10)).foregroundStyle(TerminalStyle.muted)
                Spacer(minLength: 0)
                Button { Task { await model.choose(.normal, sleep: true) } } label: {
                    TerminalLabel("立即休眠", systemImage: "power")
                }.workKeyboardFocus(radius: 0).disabled(model.busy)
            }
        }.padding(.horizontal, 16).padding(.vertical, 12).background(.white)
    }

    private var rule: some View { Rectangle().fill(TerminalStyle.line.opacity(0.6)).frame(height: 1) }
    private var displaySummary: String {
        model.display.lidClosed.map { $0 ? "上盖已合上" : "上盖已打开" } ?? "上盖状态未知"
    }
}
