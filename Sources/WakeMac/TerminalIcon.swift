import SwiftUI

/// Shared monochrome symbols keep the same optical weight and layout slots on every surface.
struct TerminalIcon: View {
    let name: String
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.monochrome)
            .fontWeight(.regular)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct TerminalLabel: View {
    let title: String
    let icon: String
    init(_ title: String, systemImage: String) { self.title = title; icon = systemImage }
    var body: some View { HStack(spacing: 7) { TerminalIcon(name: icon); Text(title) } }
}
