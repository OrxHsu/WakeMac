import SwiftUI

enum ScheduleCalendar {
    static func days(in month: Date, calendar: Calendar) -> [Date?] {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start,
              let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.map {
            calendar.date(byAdding: .day, value: $0 - 1, to: start)
        }
    }

    static func date(day: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = hour; parts.minute = minute; parts.second = 0
        guard let value = calendar.date(from: parts) else { return nil }
        // Reject nonexistent local times rather than silently shifting a DST gap.
        let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: value)
        guard actual.year == parts.year, actual.month == parts.month, actual.day == parts.day,
              actual.hour == hour, actual.minute == minute else { return nil }
        return value
    }
}

struct SchedulePicker: View {
    @Binding var selection: Date
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 9) {
                TerminalIcon(name: "calendar")
                Text(selection.formatted(.dateTime.month(.twoDigits).day(.twoDigits).locale(Locale(identifier: "zh_CN"))))
                Rectangle().fill(WorkStyle.line).frame(width: 1, height: 14)
                Text(selection.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "en_GB"))))
                    .monospacedDigit()
                TerminalIcon(name: "chevron.down").font(.system(size: 9, weight: .semibold))
            }.font(.system(size: 12, weight: .medium))
        }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0).accessibilityLabel("选择恢复日期和时间")
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                SchedulePickerPanel(initial: selection) { value in
                    if let value { selection = value }
                    showing = false
                }
            }
    }
}

private struct SchedulePickerPanel: View {
    let finish: (Date?) -> Void
    private let calendar: Calendar
    @State private var day: Date
    @State private var month: Date
    @State private var hour: Int
    @State private var minute: Int
    @State private var error = ""

    init(initial: Date, finish: @escaping (Date?) -> Void) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current; calendar.firstWeekday = 2
        self.calendar = calendar; self.finish = finish
        let initial = max(initial, Date().addingTimeInterval(60))
        _day = State(initialValue: initial)
        _month = State(initialValue: calendar.dateInterval(of: .month, for: initial)!.start)
        _hour = State(initialValue: calendar.component(.hour, from: initial))
        _minute = State(initialValue: calendar.component(.minute, from: initial))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("选择恢复时间").font(WorkType.sectionTitle).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("今天") { day = context.date; month = calendar.dateInterval(of: .month, for: day)!.start }
                        .buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0).foregroundStyle(WorkStyle.blue).font(.system(size: 11, weight: .medium))
                }
                HStack {
                    Text(month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN"))))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    monthButton(-1, now: context.date)
                    monthButton(1, now: context.date)
                }
                VStack(spacing: 7) {
                    HStack(spacing: 4) {
                        ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { name in
                            Text(name).font(.system(size: 10, weight: .medium))
                                .foregroundStyle(WorkStyle.muted).frame(maxWidth: .infinity)
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 5) {
                        let days = ScheduleCalendar.days(in: month, calendar: calendar)
                        ForEach(days.indices, id: \.self) { index in
                            if let value = days[index] { dayButton(value, now: context.date) }
                            else { Color.clear.frame(height: 32).accessibilityHidden(true) }
                        }
                    }
                }
                Divider()
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("时间").font(.system(size: 12, weight: .medium))
                        Text("24 小时制 · 本地时间").font(.system(size: 10)).foregroundStyle(WorkStyle.muted)
                    }
                    Spacer()
                    timeMenu(value: $hour, range: 0..<24, unit: "小时")
                    Text(":").font(.system(size: 20, weight: .medium)).foregroundStyle(WorkStyle.muted)
                    timeMenu(value: $minute, range: 0..<60, unit: "分钟")
                }
                let result = ScheduleCalendar.date(day: day, hour: hour, minute: minute, calendar: calendar)
                if !error.isEmpty {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                } else if result == nil || result! <= context.date {
                    Text("请选择一个未来的有效时间").font(.system(size: 11)).foregroundStyle(WorkStyle.muted)
                }
                HStack {
                    Button("取消") { finish(nil) }.buttonStyle(WorkButtonStyle()).workKeyboardFocus(radius: 0)
                    Spacer()
                    Button("完成") {
                        guard let value = result, value > Date() else { error = "这个时间已经过去，请重新选择。"; return }
                        finish(value)
                    }.buttonStyle(WorkButtonStyle(prominent: true)).workKeyboardFocus(radius: 0).disabled(result == nil || result! <= context.date)
                }
            }.padding(20).frame(width: 332).background(WorkStyle.surface).preferredColorScheme(.light)
                .foregroundStyle(WorkStyle.ink).tint(WorkStyle.blue)
                .onChange(of: day) { _, _ in error = "" }
                .onChange(of: hour) { _, _ in error = "" }
                .onChange(of: minute) { _, _ in error = "" }
                .onExitCommand { finish(nil) }
        }
    }

    private func monthButton(_ offset: Int, now: Date) -> some View {
        Button { month = calendar.date(byAdding: .month, value: offset, to: month)! } label: {
            TerminalIcon(name: offset < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 11, weight: .semibold)).frame(width: 26, height: 26)
        }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
            .accessibilityLabel(offset < 0 ? "上个月" : "下个月")
            .disabled(offset < 0 && month <= calendar.dateInterval(of: .month, for: now)!.start)
    }

    private func dayButton(_ value: Date, now: Date) -> some View {
        let selected = calendar.isDate(value, inSameDayAs: day)
        let past = value < calendar.startOfDay(for: now)
        return Button { day = value } label: {
            Text("\(calendar.component(.day, from: value))")
                .font(.system(size: 12, weight: selected ? .semibold : .regular, design: .rounded))
                .frame(maxWidth: .infinity).frame(height: 32)
                .foregroundStyle(selected ? Color.white : past ? WorkStyle.muted.opacity(0.35) : WorkStyle.ink)
                .background(selected ? WorkStyle.blue : .clear, in: RoundedRectangle(cornerRadius: 0))
                .overlay(RoundedRectangle(cornerRadius: 0).strokeBorder(calendar.isDateInToday(value) && !selected ? TerminalStyle.amber.opacity(0.8) : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 0))
        }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0).disabled(past)
            .accessibilityLabel(value.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func timeMenu(value: Binding<Int>, range: Range<Int>, unit: String) -> some View {
        TerminalPicker("选择" + unit, selection: value, choices: range.map { TerminalChoice(String(format: "%02d", $0), $0) })
            .frame(width: 66).accessibilityValue(String(value.wrappedValue))
    }
}
