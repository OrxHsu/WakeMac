import SwiftUI
import AppKit

enum WorkStyle {
    static let blue = Color(light: 0x2563EB, dark: 0x79A9FF)
    static let canvas = Color(light: 0xF7F9FC, dark: 0x171B23)
    static let surface = Color(light: 0xFFFFFF, dark: 0x202631)
    static let sidebar = Color(light: 0xEDF2F9, dark: 0x131720)
    static let selection = Color(light: 0xEAF1FF, dark: 0x253955)
    static let line = Color(light: 0xE3E8F0, dark: 0x333D4D)
    static let ink = Color(light: 0x19283D, dark: 0xECF1FA)
    static let muted = Color(light: 0x65748A, dark: 0xA2AFC2)
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

struct WorkButtonStyle: PrimitiveButtonStyle {
    var prominent = false
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                    .buttonStyle(.glassProminent).tint(Color.blue).controlSize(.large)
            } else {
                Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                    .buttonStyle(.glass).controlSize(.large)
            }
        } else {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                .buttonStyle(.bordered).controlSize(.large)
        }
    }
}

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
    @ViewBuilder func workGlassControl() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
        } else { self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) }
    }
}

struct WorkCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .semibold))
                if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(WorkStyle.muted).fixedSize(horizontal: false, vertical: true) }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(22)
        .background(WorkStyle.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(WorkStyle.line.opacity(0.5)))
    }
}

struct WorkNote: View {
    let text: String
    var icon = "info.circle"
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).padding(.top, 1)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
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
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(WorkStyle.blue.opacity(focused ? 0.65 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func workKeyboardFocus(radius: CGFloat) -> some View {
        modifier(WorkKeyboardFocus(radius: radius))
    }
}
