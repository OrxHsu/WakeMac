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
    var standalone = false
    private var protected: Bool { model.snapshot?.lockPolicy == .immediate }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: MenuMark.image()).renderingMode(.template)
                    .foregroundStyle(WorkStyle.muted).frame(width: 20, height: 20)
                Text("WakeMac").font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button { model.openPreferences?() } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 14))
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(WorkStyle.muted)
                    .workKeyboardFocus(radius: 8)
                    .accessibilityLabel("打开主窗口").help("工作模式与设置")
            }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 8) {
                Text(model.busy ? "正在切换" : model.pending != nil ? "等待确认" : model.error ? "需要检查" : model.active?.title ?? "读取状态")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                HStack(spacing: 6) {
                    Circle().fill(model.error ? Color.orange : WorkStyle.blue).frame(width: 5, height: 5)
                    Text(model.headline).font(.system(size: 11, weight: .medium))
                    Spacer()
                    if let battery = model.battery {
                        Image(systemName: battery.onBattery ? "battery.75percent" : "bolt.fill")
                        Text("\(battery.percent)%").monospacedDigit()
                    }
                }.font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
            }.padding(.horizontal, 24).padding(.bottom, 22)

            PowerControls(model: model, compact: true)
                .padding(16)
                .background(WorkStyle.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16).padding(.bottom, 16)

            VStack(spacing: 4) {
                ForEach(WorkMode.allCases, id: \.self) { mode in modeRow(mode) }
            }.padding(.horizontal, 12)

            if let countdown = model.countdownText {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                    Text(countdown).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("取消", action: model.cancelVisibleCountdown).buttonStyle(.plain)
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(WorkStyle.blue)
                    .padding(12).background(WorkStyle.selection, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 16).padding(.top, 12)
            }
            if model.pending != nil || model.error {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.message).font(.system(size: 11)).foregroundStyle(model.error ? Color.red : WorkStyle.muted)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    HStack {
                        if model.pending != nil { Button("打开系统设置", action: model.openLockSettings) }
                        Button("重新检查") { model.error = false; Task { await model.refresh() } }
                    }.buttonStyle(WorkButtonStyle())
                }.padding(16)
            }
            HStack(spacing: 6) {
                Image(systemName: protected ? "lock.shield" : "lock.trianglebadge.exclamationmark")
                Text(protected ? "锁屏保护已开启" : "等待核验锁屏保护")
                Spacer()
                Text("解锁后可操作").foregroundStyle(WorkStyle.muted)
            }.font(.system(size: 10)).foregroundStyle(WorkStyle.muted)
                .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 16)

            Rectangle().fill(WorkStyle.line.opacity(0.6)).frame(height: 1).padding(.horizontal, 20)
            HStack {
                Label(displaySummary, systemImage: "laptopcomputer").font(.system(size: 10)).foregroundStyle(WorkStyle.muted)
                Spacer()
                Button { Task { await model.choose(.normal, sleep: true) } } label: {
                    Label("立即休眠", systemImage: "power").font(.system(size: 11, weight: .medium))
                }.buttonStyle(.plain).disabled(model.busy)
            }.padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 344).fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(WorkStyle.ink)
        .background { if standalone { WorkWindowMaterial() } }
        .tint(WorkStyle.blue)
    }
    private func modeRow(_ mode: WorkMode) -> some View {
        let selected = model.active == mode && model.pending == nil && !model.error
        return Button {
            model.quitWhenReady = false
            Task { await model.choose(mode) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: rowIcon(mode)).font(.system(size: 17, weight: .regular))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(selected ? WorkStyle.blue : WorkStyle.muted)
                    .background(selected ? WorkStyle.blue.opacity(0.13) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    Text(mode.title).font(.system(size: 13, weight: .semibold))
                    Text(subtitle(mode)).font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16)).foregroundStyle(selected ? WorkStyle.blue : WorkStyle.line)
            }.foregroundStyle(WorkStyle.ink)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(selected ? WorkStyle.blue.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? WorkStyle.blue.opacity(0.14) : Color.clear))
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).disabled(model.busy)
            .workKeyboardFocus(radius: 16)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private func rowIcon(_ mode: WorkMode) -> String {
        switch mode { case .background: "laptopcomputer"; case .desk: "display"; case .normal: "moon.zzz" }
    }
    private func subtitle(_ mode: WorkMode) -> String {
        switch mode {
        case .background: "合上屏幕，任务继续"
        case .desk: "保持运行，闲时熄屏"
        case .normal: "恢复休眠，安心离开"
        }
    }
    private var displaySummary: String {
        model.display.lidClosed.map { $0 ? "上盖已合上" : "上盖已打开" } ?? "上盖状态未知"
    }
}
