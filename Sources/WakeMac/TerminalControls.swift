import SwiftUI

struct TerminalChoice<Value: Hashable> {
    let title: String
    let value: Value
    init(_ title: String, _ value: Value) { self.title = title; self.value = value }
}

struct TerminalPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [TerminalChoice<Value>]
    init(_ title: String, selection: Binding<Value>, choices: [TerminalChoice<Value>]) {
        self.title = title; _selection = selection; self.choices = choices
    }
    var body: some View {
        TerminalMenuControl(title: title, value: choices.first { $0.value == selection }?.title ?? "请选择",
                            titles: choices.map(\.title), selected: choices.firstIndex { $0.value == selection }) { index in
            guard choices.indices.contains(index) else { return }
            selection = choices[index].value
        }
    }
}

struct TerminalActionMenu: View {
    let title: String
    let titles: [String]
    var action: (Int) -> Void
    var body: some View { TerminalMenuControl(title: title, value: title, titles: titles, selected: nil, action: action) }
}

private struct TerminalMenuControl: View {
    let title: String
    let value: String
    let titles: [String]
    let selected: Int?
    let action: (Int) -> Void
    @State private var showing = false
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 6) {
                Text(value).font(WorkType.body).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TerminalIcon(name: "chevron.down", size: 12).foregroundStyle(TerminalStyle.accent)
                    .frame(width: 24, height: 24).background(TerminalStyle.silver)
            }.padding(.leading, 9).padding(.trailing, 3).frame(height: 32)
                .background(WorkStyle.surface)
                .overlay(Rectangle().strokeBorder(showing ? TerminalStyle.ink.opacity(0.65) : TerminalStyle.line))
                .opacity(enabled && !titles.isEmpty ? 1 : 0.45).contentShape(Rectangle())
        }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0).disabled(titles.isEmpty)
            .accessibilityLabel(title).accessibilityValue(value).accessibilityHint("展开选项；方向键选择，回车确认，Esc 取消")
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                TerminalMenuPanel(title: title, titles: titles, selected: selected) { index in
                    if let index { action(index) }
                    showing = false
                }.preferredColorScheme(.light)
            }
    }
}

private struct TerminalMenuPanel: View {
    let title: String
    let titles: [String]
    let selected: Int?
    let finish: (Int?) -> Void
    @State private var highlighted = 0
    @FocusState private var keyboardFocus: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(WorkType.caption).foregroundStyle(TerminalStyle.muted)
                .padding(.horizontal, 12).padding(.vertical, 9)
            Rectangle().fill(TerminalStyle.line).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(titles.indices, id: \.self) { index in
                            Button { finish(index) } label: {
                                HStack(spacing: 8) {
                                    TerminalIcon(name: selected == index ? "checkmark" : "square", size: 12)
                                        .foregroundStyle(selected == index ? TerminalStyle.accent : TerminalStyle.line)
                                    Text(titles[index]).font(WorkType.body).lineLimit(2)
                                    Spacer(minLength: 0)
                                }.padding(.horizontal, 9).frame(minHeight: 32)
                                    .foregroundStyle(TerminalStyle.ink)
                                    .background(highlighted == index ? TerminalStyle.selection : .clear)
                                    .overlay(alignment: .leading) { Rectangle().fill(TerminalStyle.accent).frame(width: 2).opacity(highlighted == index ? 1 : 0) }
                                    .contentShape(Rectangle())
                            }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0).id(index)
                                .accessibilityAddTraits(selected == index ? [.isSelected] : [])
                                .onHover { if $0 { highlighted = index } }
                        }
                    }.padding(4)
                }.frame(height: CGFloat(min(titles.count, 9)) * 34 + 8)
                    .onChange(of: highlighted) { _, index in proxy.scrollTo(index) }
                    .onAppear { if let selected { proxy.scrollTo(selected) } }
            }
        }.frame(width: 260).background(WorkStyle.surface).terminalReveal()
            .overlay(Rectangle().strokeBorder(TerminalStyle.line))
            .focusable().focusEffectDisabled().focused($keyboardFocus)
            .onAppear { highlighted = selected ?? 0; keyboardFocus = true }
            .onKeyPress(.downArrow) { highlighted = min(titles.count - 1, highlighted + 1); return .handled }
            .onKeyPress(.upArrow) { highlighted = max(0, highlighted - 1); return .handled }
            .onKeyPress(.return) { if titles.indices.contains(highlighted) { finish(highlighted) }; return .handled }
            .onExitCommand { finish(nil) }
    }
}

struct TerminalTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).padding(.horizontal, 9).padding(.vertical, 7)
            .background(WorkStyle.surface)
            .overlay(Rectangle().strokeBorder(TerminalStyle.line))
    }
}

struct TerminalStepper<Value, Content: View>: View where Value: Strideable, Value.Stride: SignedNumeric & Comparable {
    @Binding var value: Value
    let range: ClosedRange<Value>
    let step: Value.Stride
    @ViewBuilder let label: Content
    var accessibilityTitle = ""
    @Environment(\.isEnabled) private var enabled
    init(value: Binding<Value>, in range: ClosedRange<Value>, step: Value.Stride = 1, @ViewBuilder label: () -> Content) {
        _value = value; self.range = range; self.step = step; self.label = label()
    }
    init(_ title: String, value: Binding<Value>, in range: ClosedRange<Value>, step: Value.Stride = 1) where Content == EmptyView {
        _value = value; self.range = range; self.step = step; label = EmptyView(); accessibilityTitle = title
    }
    var body: some View {
        HStack(spacing: 8) {
            label
            HStack(spacing: 0) {
                Button { value = max(range.lowerBound, value.advanced(by: -step)) } label: { Text("−").frame(width: 24, height: 26) }
                    .workKeyboardFocus(radius: 0).disabled(value <= range.lowerBound).accessibilityLabel("减少" + accessibilityTitle)
                Rectangle().fill(TerminalStyle.line).frame(width: 1, height: 26)
                Button { value = min(range.upperBound, value.advanced(by: step)) } label: { Text("+").frame(width: 24, height: 26) }
                    .workKeyboardFocus(radius: 0).disabled(value >= range.upperBound).accessibilityLabel("增加" + accessibilityTitle)
            }.font(TerminalStyle.mono(14)).buttonStyle(TerminalPlainButtonStyle()).focusEffectDisabled().background(TerminalStyle.silver.opacity(0.5))
                .overlay(Rectangle().strokeBorder(TerminalStyle.line))
        }
        .accessibilityValue(String(describing: value))
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            switch direction {
            case .increment: value = min(range.upperBound, value.advanced(by: step))
            case .decrement: value = max(range.lowerBound, value.advanced(by: -step))
            @unknown default: break
            }
        }
    }
}

struct TerminalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let title: String
    @Environment(\.isEnabled) private var enabled
    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) {
        self.title = title; _value = value; self.range = range
    }
    private var fraction: Double { min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound))) }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(TerminalStyle.silver).frame(height: 6)
                    .overlay(Rectangle().strokeBorder(TerminalStyle.line))
                Rectangle().fill(TerminalStyle.accent).frame(width: max(0, geometry.size.width * fraction), height: 6)
                Rectangle().fill(WorkStyle.surface).frame(width: 12, height: 20)
                    .overlay(Rectangle().strokeBorder(TerminalStyle.ink.opacity(0.6)))
                    .offset(x: max(0, (geometry.size.width - 12) * fraction))
            }.frame(height: 24).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    guard enabled else { return }
                    value = range.lowerBound + min(1, max(0, drag.location.x / max(1, geometry.size.width))) * (range.upperBound - range.lowerBound)
                })
        }.frame(height: 24).opacity(enabled ? 1 : 0.4)
            .focusable().workKeyboardFocus(radius: 0)
            .onKeyPress(.leftArrow) { adjust(-1); return enabled ? .handled : .ignored }
            .onKeyPress(.rightArrow) { adjust(1); return enabled ? .handled : .ignored }
            .accessibilityElement().accessibilityLabel(title)
            .accessibilityValue(value.formatted(.percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                let delta = (range.upperBound - range.lowerBound) / 20
                switch direction {
                case .increment: value = min(range.upperBound, value + delta)
                case .decrement: value = max(range.lowerBound, value - delta)
                @unknown default: break
                }
            }
    }
    private func adjust(_ direction: Double) {
        guard enabled else { return }
        value = min(range.upperBound, max(range.lowerBound, value + direction * (range.upperBound - range.lowerBound) / 20))
    }
}
