// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import AppKit
import CoreText
import SwiftUI

/// Light silver hardware, worn cobalt controls and amber section marks.
enum TerminalStyle {
    static let ink = Color(hex: 0x242A30)
    static let muted = Color(hex: 0x65717D)
    static let line = Color(hex: 0xA5AFB9)
    static let paper = Color(hex: 0xF3F5F7)
    static let silver = Color(hex: 0xE0E5EA)
    static let accent = Color(hex: 0x002FA7)
    static let selection = Color(hex: 0xE4E9F7)
    static let amber = Color(hex: 0xC28B39)
    static let steel = Color(hex: 0x5D7D9B)
    static let warning = Color(hex: 0x965F50)
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    static func mono(_ size: CGFloat) -> Font { .custom("IBMPlexMono", size: size) }

    @MainActor static func registerFonts() {
        for file in ["IBMPlexMono-Regular"] {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct TerminalFrame: Shape {
    var cut: CGFloat = 0
    func path(in r: CGRect) -> Path {
        let c = min(cut, min(r.width, r.height) / 2)
        return Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

struct TerminalBrackets: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            for (x, y, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0),
                                  (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
                p.move(to: CGPoint(x: x + dx * 8, y: y))
                p.addLine(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x, y: y + dy * 8))
            }
        }
    }
}

struct TerminalGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for x in stride(from: CGFloat(0), through: size.width, by: 16) {
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: CGFloat(0), through: size.height, by: 16) {
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(TerminalStyle.line.opacity(0.12)), lineWidth: 0.5)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Flat command fields; color carries emphasis, never a bevel or clipped corner.
struct TerminalButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        TerminalButtonBody(configuration: configuration, prominent: prominent, enabled: enabled, reduceMotion: reduceMotion)
    }
    private struct TerminalButtonBody: View {
        let configuration: Configuration
        let prominent: Bool
        let enabled: Bool
        let reduceMotion: Bool
        @State private var hovered = false
        var body: some View {
            configuration.label.font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 15).frame(minHeight: 34)
                .foregroundStyle(prominent ? .white : TerminalStyle.ink)
                .background(prominent ? TerminalStyle.accent : hovered && enabled ? TerminalStyle.selection : .white)
                .overlay(Rectangle().strokeBorder(prominent ? TerminalStyle.ink.opacity(0.2) : TerminalStyle.line.opacity(0.7)))
                .opacity(enabled ? 1 : 0.4)
                .offset(y: configuration.isPressed && !reduceMotion ? 1 : 0)
                .brightness(configuration.isPressed ? -0.07 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovered)
                .onHover { hovered = $0 }
        }
    }
}

/// Borderless actions share the same tactile feedback without adding chrome.
struct TerminalPlainButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed && !reduceMotion ? 1 : 0)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// NoMe's binary field: status text and a fixed square lamp, with no sliding thumb.
struct TerminalSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 7) {
                Text(configuration.isOn ? "ON" : "OFF")
                    .font(.system(size: 10, weight: .medium)).frame(width: 25)
                    .contentTransition(.opacity)
                Rectangle().fill(configuration.isOn ? .white : TerminalStyle.silver)
                    .frame(width: 14, height: 14)
                    .overlay(Rectangle().strokeBorder(configuration.isOn ? .white.opacity(0.8) : TerminalStyle.line))
                    .overlay {
                        Rectangle().fill(TerminalStyle.accent).frame(width: 6, height: 6)
                            .scaleEffect(configuration.isOn ? 1 : 0.5)
                            .opacity(configuration.isOn ? 1 : 0)
                    }
            }.foregroundStyle(configuration.isOn ? .white : TerminalStyle.muted)
                .padding(.horizontal, 8).frame(height: 30)
                .background(configuration.isOn ? TerminalStyle.accent : .white)
                .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.7)))
                .opacity(enabled ? 1 : 0.4)
                .padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: configuration.isOn)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
            }
    }
}

extension View {
    func terminalSurface(cut: CGFloat = 0) -> some View {
        background(TerminalStyle.paper)
            .clipShape(TerminalFrame(cut: cut))
            .overlay(TerminalFrame(cut: cut).stroke(TerminalStyle.line, lineWidth: 1))
            .overlay(TerminalBrackets().stroke(TerminalStyle.muted, lineWidth: 0.7).padding(6).allowsHitTesting(false))
    }
}

private struct TerminalReveal: ViewModifier {
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 10)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { visible = true } }
    }
}

extension View {
    func terminalReveal() -> some View { modifier(TerminalReveal()) }
}
