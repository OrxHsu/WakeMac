import SwiftUI

/// Original 16-unit glyphs: one grid and one stroke weight across every app surface.
struct TerminalIcon: View {
    let name: String
    var size: CGFloat = 16
    var body: some View {
        TerminalGlyph(name: name).fill(.foreground, style: FillStyle(antialiased: false))
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

private struct TerminalGlyph: Shape {
    let name: String
    func path(in r: CGRect) -> Path {
        var path = Path()
        func dot(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1) {
            path.addRect(CGRect(x: r.minX + CGFloat(x) * r.width / 16,
                                y: r.minY + CGFloat(y) * r.height / 16,
                                width: CGFloat(w) * r.width / 16, height: CGFloat(h) * r.height / 16))
        }
        func line(_ x: Int, _ y: Int, _ endX: Int, _ endY: Int) {
            var x = x, y = y
            let dx = abs(endX - x), dy = -abs(endY - y)
            let sx = x < endX ? 1 : -1, sy = y < endY ? 1 : -1
            var error = dx + dy
            while true {
                dot(x, y)
                if x == endX && y == endY { break }
                let twice = error * 2
                if twice >= dy { error += dy; x += sx }
                if twice <= dx { error += dx; y += sy }
            }
        }
        func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
            dot(x, y, w); dot(x, y + h - 1, w); dot(x, y, 1, h); dot(x + w - 1, y, 1, h)
        }
        if name.contains("laptop") {
            box(3, 3, 10, 9); dot(1, 12, 14); dot(6, 13, 4)
        } else if name.contains("display") || name == "desktopcomputer" {
            box(2, 2, 12, 9); dot(7, 11, 2, 3); dot(4, 14, 8)
        } else if name.contains("sun") {
            box(5, 5, 6, 6); dot(7, 1, 2, 2); dot(7, 13, 2, 2); dot(1, 7, 2, 2); dot(13, 7, 2, 2)
            line(2, 2, 3, 3); line(12, 3, 13, 2); line(2, 13, 3, 12); line(12, 12, 13, 13)
        } else if name.contains("moon") {
            line(7, 1, 3, 5); dot(2, 6, 1, 5); line(3, 11, 6, 14); dot(7, 14, 4)
            line(11, 13, 14, 10); line(7, 1, 6, 4); dot(6, 5, 1, 3); line(7, 8, 9, 10); dot(10, 10, 4)
        } else if name.contains("bolt") && !name.contains("battery") {
            line(9, 1, 3, 8); dot(3, 8, 5); line(7, 9, 6, 14); line(6, 14, 13, 6); dot(9, 6, 5); line(9, 1, 9, 5)
        } else if name.contains("terminal") {
            box(1, 3, 14, 10); line(4, 6, 6, 8); line(6, 8, 4, 10); dot(8, 10, 4)
        } else if name.contains("slider") || name.contains("gear") {
            for (y, x) in [(4, 10), (8, 4), (12, 8)] { dot(1, y, 14); box(x, y - 1, 3, 3) }
        } else if name.contains("paint") {
            line(5, 9, 12, 2); line(7, 11, 14, 4); line(12, 2, 14, 4)
            box(3, 10, 5, 4); dot(2, 14, 4)
        } else if name.contains("calendar") {
            box(2, 3, 12, 11); dot(5, 1, 1, 4); dot(10, 1, 1, 4); dot(3, 6, 10)
            for y in [8, 11] { for x in [4, 7, 10] { dot(x, y, 2) } }
        } else if name.contains("shield") || name.hasPrefix("lock") {
            dot(6, 1, 4); line(2, 3, 6, 1); line(9, 1, 13, 3); dot(2, 4, 1, 6); dot(13, 4, 1, 6)
            line(2, 10, 7, 14); line(8, 14, 13, 10)
            if name.contains("exclamation") { dot(7, 4, 2, 5); dot(7, 10, 2) }
            else { line(5, 7, 7, 9); line(7, 9, 10, 5) }
        } else if name.contains("power") {
            dot(7, 1, 2, 7); line(4, 3, 2, 6); dot(2, 7, 1, 4); line(2, 11, 5, 14)
            dot(6, 14, 4); line(10, 14, 13, 11); dot(13, 6, 1, 5); line(11, 3, 13, 5)
        } else if name == "play.fill" {
            for y in 3...12 { dot(5, y, min(y - 2, 13 - y)) }
        } else if name == "key" {
            box(1, 2, 6, 6); line(6, 7, 13, 14); dot(10, 12, 3); dot(12, 10, 2)
        } else if name.contains("battery") {
            box(1, 4, 12, 8); dot(13, 6, 2, 4); dot(3, 6, 7, 4)
        } else if name.contains("drive") {
            box(2, 5, 12, 8); line(2, 5, 4, 2); dot(4, 2, 8); line(11, 2, 13, 5)
            dot(4, 9, 2, 2); dot(9, 9, 2, 2)
        } else if name.contains("clock") || name.contains("timer") || name.contains("hourglass") {
            dot(5, 2, 6); dot(2, 5, 1, 6); dot(13, 5, 1, 6); dot(5, 13, 6)
            line(2, 5, 5, 2); line(10, 2, 13, 5); line(2, 10, 5, 13); line(10, 13, 13, 10)
            dot(7, 4, 1, 5); dot(8, 8, 3)
            if name.contains("arrow") { dot(1, 1, 1, 4); dot(1, 4, 4) }
            if name.contains("timer") { dot(6, 0, 4) }
        } else if name.contains("chevron") || name.contains("arrow") {
            if name.contains("left") { line(10, 3, 5, 8); line(5, 8, 10, 13) }
            else if name.contains("up") { line(3, 10, 8, 5); line(8, 5, 13, 10) }
            else if name.contains("down") { line(3, 5, 8, 10); line(8, 10, 13, 5) }
            else { line(5, 3, 10, 8); line(10, 8, 5, 13); if name.contains("arrow") { dot(1, 8, 9) } }
        } else if name.contains("minus") { box(2, 2, 12, 12); dot(5, 7, 6, 2) }
        else if name.contains("checkmark") { line(2, 8, 6, 12); line(6, 12, 13, 4) }
        else if name.contains("info") || name.contains("exclamation") || name.contains("question") {
            box(2, 2, 12, 12); dot(7, 4, 2, 2); dot(7, 7, 2, 4)
        } else if name.contains("fill") { dot(4, 4, 8, 8) }
        else { box(3, 3, 10, 10) }
        return path
    }
}

struct TerminalLabel: View {
    let title: String
    let icon: String
    init(_ title: String, systemImage: String) { self.title = title; icon = systemImage }
    var body: some View { HStack(spacing: 7) { TerminalIcon(name: icon); Text(title) } }
}
