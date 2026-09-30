// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import SwiftUI
import AppKit

enum WorkStyle {
    static let cardRadius: CGFloat = 0
    static let inputRadius: CGFloat = 0
    static let blue = TerminalStyle.accent
    static let canvas = TerminalStyle.paper
    static let surface = Color.white
    static let sidebar = TerminalStyle.silver
    static let selection = TerminalStyle.selection
    static let line = TerminalStyle.line.opacity(0.55)
    static let ink = TerminalStyle.ink
    static let muted = TerminalStyle.muted
}

/// Shared semantic hierarchy for the main window, sheets, and compact panel.
enum WorkType {
    static let pageTitle = Font.system(size: 28, weight: .semibold, design: .default)
    static let sectionTitle = TerminalStyle.display(17)
    static let dialogTitle = TerminalStyle.display(22)
    static let controlLabel = Font.system(size: 13, weight: .regular)
    static let body = Font.system(size: 12, weight: .regular)
    static let caption = Font.system(size: 11, weight: .regular)
    static let compactLabel = Font.system(size: 12, weight: .regular)
    static let compactCaption = Font.system(size: 10, weight: .regular)
}

// Use the style itself so SwiftUI installs its enabled / reduced-motion environment.
typealias WorkButtonStyle = TerminalButtonStyle

/// Native macOS backdrop sampling; the window stays transparent so the
/// material responds to the desktop rather than an opaque painted surface.
struct WorkGlassBackground: NSViewRepresentable {
    var radius: CGFloat = 24
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = radius
            return glass
        }
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        return material
    }
    func updateNSView(_ view: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            glass.cornerRadius = radius
        }
    }
}

struct WorkGlassGroup<Content: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { content }
        } else { content }
    }
}

extension View {
    func workGlassControl() -> some View {
        self.padding(1).background(WorkStyle.surface)
            .overlay(TerminalFrame(cut: 4).stroke(TerminalStyle.line))
    }
}

struct WorkCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(WorkType.sectionTitle).accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(WorkType.caption).foregroundStyle(WorkStyle.muted).fixedSize(horizontal: false, vertical: true) }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(22)
        .background(WorkStyle.surface)
        .clipShape(TerminalFrame(cut: 8))
        .overlay(TerminalFrame(cut: 8).stroke(TerminalStyle.line))
        .overlay(alignment: .topLeading) { Rectangle().fill(TerminalStyle.amber.opacity(0.7)).frame(width: 26, height: 2).padding(.leading, 22) }
    }
}

struct WorkToggle: View {
    let title: String
    var detail: String? = nil
    var icon: String? = nil
    var compact = false
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                TerminalIcon(name: icon).font(.system(size: compact ? 15 : 18))
                    .foregroundStyle(isOn ? WorkStyle.blue : WorkStyle.muted).frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(compact ? WorkType.compactLabel : WorkType.controlLabel)
                if let detail { Text(detail).font(compact ? WorkType.compactCaption : WorkType.caption).foregroundStyle(WorkStyle.muted)
                    .fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(TerminalSwitchStyle()).controlSize(.small)
                .accessibilityLabel(title).accessibilityHint(detail ?? "")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkNote: View {
    let text: String
    var icon = "info.circle"
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            TerminalIcon(name: icon).frame(width: 22)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    // Align the glyph's optical center with the first line's cap height.
                    dimensions.height / 2 + NSFont.systemFont(ofSize: 11).capHeight / 2
                }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }.font(WorkType.caption).foregroundStyle(WorkStyle.muted)
    }
}

/// Content-only vibrancy: NSWindow owns the outside corner and titlebar.
struct WorkWindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .windowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct WorkKeyboardFocus: ViewModifier {
    let radius: CGFloat
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.focused($focused).focusEffectDisabled()
            .overlay(alignment: .bottom) {
                Rectangle().fill(TerminalStyle.amber)
                    .frame(width: 16, height: 2).offset(y: 3)
                    .opacity(focused ? 1 : 0).allowsHitTesting(false)
            }
    }
}

extension View {
    func workKeyboardFocus(radius: CGFloat) -> some View {
        modifier(WorkKeyboardFocus(radius: radius))
    }
}
