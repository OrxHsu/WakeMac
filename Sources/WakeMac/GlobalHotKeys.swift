import AppKit
import Carbon

struct ShortcutBinding: Codable, Equatable, Identifiable {
    var id: UInt32
    var key: UInt32
    var modifiers: UInt32
    static let defaults = [Self(id: 1, key: 18, modifiers: UInt32(controlKey | optionKey)), Self(id: 2, key: 19, modifiers: UInt32(controlKey | optionKey)), Self(id: 3, key: 20, modifiers: UInt32(controlKey | optionKey))]
    var title: String { id == 1 ? "后台工作" : id == 2 ? "桌面工作" : "正常休眠" }
}
@MainActor final class GlobalHotKeys: ObservableObject {
    @Published var bindings = ShortcutBinding.defaults
    @Published var enabled = true
    @Published var message = ""
    var handler: ((UInt32) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private let preferences: UserDefaults
    static let keys: [(String, UInt32)] = [("1",18),("2",19),("3",20),("4",21),("5",23),("6",22),("7",26),("8",28),("9",25),("0",29),("A",0),("B",11),("C",8),("D",2),("E",14),("F",3),("G",5),("H",4),("I",34),("J",38),("K",40),("L",37),("M",46),("N",45),("O",31),("P",35),("Q",12),("R",15),("S",1),("T",17),("U",32),("V",9),("W",13),("X",7),("Y",16),("Z",6)]
    static let modifiers: [(String, UInt32)] = [("⌃⌥", UInt32(controlKey | optionKey)), ("⌃⌥⌘", UInt32(controlKey | optionKey | cmdKey)), ("⌘⇧", UInt32(cmdKey | shiftKey))]
    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        if let data = preferences.data(forKey: "Shortcuts"), let saved = try? JSONDecoder().decode([ShortcutBinding].self, from: data), saved.count == 3 { bindings = saved }
        enabled = preferences.object(forKey: "ShortcutsEnabled") as? Bool ?? true
    }
    func start() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard status == noErr else { return status }
            let service = Unmanaged<GlobalHotKeys>.fromOpaque(context).takeUnretainedValue()
            let id = key.id
            Task { @MainActor in service.handler?(id) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard status == noErr else { message = "无法注册快捷键事件（\(status)）。"; return }
        if enabled, let failure = register(bindings) { clear(); message = failure }
    }
    private func clear() { refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll() }
    private func register(_ values: [ShortcutBinding]) -> String? {
        for value in values {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(value.key, value.modifiers, EventHotKeyID(signature: 0x574D4F44, id: value.id), GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else { return "\(value.title)快捷键被占用或不可用（\(status)），请更换。" }
            refs.append(ref)
        }
        return nil
    }
    func apply(_ values: [ShortcutBinding], enabled newEnabled: Bool) {
        guard Set(values.map { "\($0.key):\($0.modifiers)" }).count == values.count else { message = "三个模式不能使用相同快捷键。"; return }
        let previous = bindings, wasEnabled = enabled
        clear()
        if newEnabled, let failure = register(values) {
            clear()
            if wasEnabled, let restoreFailure = register(previous) { clear(); message = failure + " 原快捷键恢复失败：" + restoreFailure; return }
            message = failure; return
        }
        bindings = values; enabled = newEnabled
        preferences.set(try? JSONEncoder().encode(values), forKey: "Shortcuts")
        preferences.set(newEnabled, forKey: "ShortcutsEnabled")
        message = newEnabled ? "快捷键已生效。" : "快捷键已关闭。"
    }
}
