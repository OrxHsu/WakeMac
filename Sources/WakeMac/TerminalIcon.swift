import SwiftUI

/// One geometric outline family: rounded strokes, no filled silhouettes or pixel grid.
struct TerminalIcon: View {
    let name: String
    var size: CGFloat = 16

    var body: some View {
        ControlGlyph(name: name)
            .stroke(.foreground, style: StrokeStyle(lineWidth: size / 16, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct ControlGlyph: Shape {
    let name: String

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func line(_ points: [CGPoint], close: Bool = false) {
            guard let first = points.first else { return }
            p.move(to: first)
            for point in points.dropFirst() { p.addLine(to: point) }
            if close { p.closeSubpath() }
        }
        func trace(_ xy: [CGFloat], close: Bool = false) {
            line(stride(from: 0, to: xy.count, by: 2).map { CGPoint(x: xy[$0], y: xy[$0 + 1]) }, close: close)
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat = 1.5) {
            p.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: radius, height: radius))
        }
        func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
            p.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        func tick() { trace([7.5, 12, 10.5, 15, 16.5, 8.5]) }
        func lightning() { trace([13, 2.5, 5.5, 13, 11, 13, 10, 21.5, 18.5, 10.5, 13, 10.5], close: true) }

        if name.contains("laptop") {
            box(4, 4.5, 16, 12, radius: 1)
            trace([2, 19, 22, 19]); trace([9, 19, 15, 19])
        } else if name.contains("display") || name == "desktopcomputer" {
            box(3, 3.5, 18, 13, radius: 1.5)
            trace([12, 16.5, 12, 20.5]); trace([8, 20.5, 16, 20.5])
        } else if name.contains("sun") {
            // A quiet activity trace conveys wakefulness without the bulky sun silhouette.
            trace([2, 13, 7, 13, 10, 5, 14, 20, 17, 10, 22, 10])
        } else if name.contains("moon") {
            p.move(to: CGPoint(x: 10, y: 3))
            p.addCurve(to: CGPoint(x: 21, y: 14), control1: CGPoint(x: 7, y: 11), control2: CGPoint(x: 13, y: 17))
            p.addCurve(to: CGPoint(x: 10, y: 3), control1: CGPoint(x: 17, y: 25), control2: CGPoint(x: 0, y: 17))
            p.closeSubpath()
        } else if name.contains("battery") {
            box(2, 6.5, 18, 11, radius: 1.5); trace([22, 10, 22, 14]); trace([6, 10, 6, 14]); trace([10, 10, 10, 14]); trace([14, 10, 14, 14])
        } else if name.contains("bolt") {
            lightning()
        } else if name.contains("terminal") {
            box(2.5, 4, 19, 16, radius: 2)
            trace([6, 9, 9, 12, 6, 15]); trace([12, 15, 17, 15])
        } else if name.contains("slider") || name.contains("gear") {
            trace([3, 6, 9, 6]); trace([13, 6, 21, 6]); circle(11, 6, 2)
            trace([3, 12, 13, 12]); trace([17, 12, 21, 12]); circle(15, 12, 2)
            trace([3, 18, 5, 18]); trace([9, 18, 21, 18]); circle(7, 18, 2)
        } else if name.contains("paint") {
            trace([8, 15, 17, 3, 21, 6, 11, 17], close: true)
            p.move(to: CGPoint(x: 8, y: 15))
            p.addCurve(to: CGPoint(x: 3, y: 21), control1: CGPoint(x: 3, y: 14), control2: CGPoint(x: 7, y: 20))
            p.addCurve(to: CGPoint(x: 11, y: 17), control1: CGPoint(x: 8, y: 23), control2: CGPoint(x: 12, y: 21))
        } else if name.contains("calendar") {
            box(3, 5, 18, 16, radius: 2); trace([7, 2.5, 7, 7]); trace([17, 2.5, 17, 7]); trace([3, 10, 21, 10])
            trace([7, 14, 9, 14]); trace([15, 14, 17, 14]); trace([7, 18, 9, 18])
        } else if name.contains("shield") || name.hasPrefix("lock") {
            p.move(to: CGPoint(x: 12, y: 2.5))
            p.addLine(to: CGPoint(x: 20, y: 6)); p.addLine(to: CGPoint(x: 20, y: 12))
            p.addCurve(to: CGPoint(x: 12, y: 21.5), control1: CGPoint(x: 20, y: 17), control2: CGPoint(x: 16, y: 20))
            p.addCurve(to: CGPoint(x: 4, y: 12), control1: CGPoint(x: 8, y: 20), control2: CGPoint(x: 4, y: 17))
            p.addLine(to: CGPoint(x: 4, y: 6)); p.closeSubpath()
            if name.contains("exclamation") { trace([12, 7, 12, 12]); circle(12, 16, 0.5) }
            else { tick() }
        } else if name.contains("power") {
            p.move(to: CGPoint(x: 6.5, y: 5.5))
            p.addCurve(to: CGPoint(x: 3.5, y: 12), control1: CGPoint(x: 4.5, y: 7), control2: CGPoint(x: 3.5, y: 9))
            p.addCurve(to: CGPoint(x: 20.5, y: 12), control1: CGPoint(x: 3.5, y: 24), control2: CGPoint(x: 20.5, y: 24))
            p.addCurve(to: CGPoint(x: 17.5, y: 5.5), control1: CGPoint(x: 20.5, y: 9), control2: CGPoint(x: 19.5, y: 7))
            trace([12, 2, 12, 12])
        } else if name.contains("play") {
            trace([7, 4, 20, 12, 7, 20], close: true)
        } else if name == "key" {
            circle(7, 8, 4.5); trace([10, 11, 20, 21, 22, 19]); trace([16, 17, 18, 15])
        } else if name.contains("drive") {
            trace([3, 13, 6, 4, 18, 4, 21, 13]); box(3, 13, 18, 7, radius: 1.5)
            circle(16, 16.5, 0.5); circle(19, 16.5, 0.5)
        } else if name.contains("hourglass") {
            trace([5, 3, 19, 3]); trace([5, 21, 19, 21])
            trace([7, 3, 7, 7, 17, 17, 17, 21]); trace([17, 3, 17, 7, 7, 17, 7, 21])
        } else if name.contains("clock") || name.contains("timer") {
            circle(12, 12.5, 8.5); trace([12, 7.5, 12, 12.5, 16, 15])
            if name.contains("timer") { trace([9, 1, 15, 1]); trace([12, 1, 12, 4]) }
            if name.contains("arrow") { trace([2.5, 4, 2.5, 9, 7.5, 9]) }
        } else if name.contains("chevron") {
            if name.contains("left") { trace([15, 5, 8, 12, 15, 19]) }
            else if name.contains("up") { trace([5, 15, 12, 8, 19, 15]) }
            else if name.contains("down") { trace([5, 9, 12, 16, 19, 9]) }
            else { trace([9, 5, 16, 12, 9, 19]) }
        } else if name.contains("arrow") {
            if name.contains("left") { trace([19, 12, 4, 12]); trace([10, 5, 3, 12, 10, 19]) }
            else { trace([4, 12, 19, 12]); trace([14, 5, 21, 12, 14, 19]) }
        } else if name.contains("minus") {
            circle(12, 12, 9); trace([8, 12, 16, 12])
        } else if name.contains("checkmark") {
            if name.contains("circle") { circle(12, 12, 9) }; tick()
        } else if name.contains("info") || name.contains("exclamation") || name.contains("question") {
            circle(12, 12, 9)
            if name.contains("exclamation") { trace([12, 6, 12, 12]); circle(12, 16, 0.5) }
            else if name.contains("question") {
                p.move(to: CGPoint(x: 9, y: 8)); p.addCurve(to: CGPoint(x: 12, y: 13), control1: CGPoint(x: 16, y: 3), control2: CGPoint(x: 18, y: 10)); trace([12, 13, 12, 14]); circle(12, 17, 0.5)
            } else { circle(12, 7, 0.5); trace([12, 11, 12, 17]) }
        } else if name.contains("circle") { circle(12, 12, 9) }
        else { box(4, 4, 16, 16, radius: 1.5) }
        return p.applying(CGAffineTransform(a: rect.width / 24, b: 0, c: 0, d: rect.height / 24, tx: rect.minX, ty: rect.minY))
    }
}

struct TerminalLabel: View {
    let title: String
    let icon: String
    init(_ title: String, systemImage: String) { self.title = title; icon = systemImage }
    var body: some View { HStack(spacing: 7) { TerminalIcon(name: icon); Text(title) } }
}
