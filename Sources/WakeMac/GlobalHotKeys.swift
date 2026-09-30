import AppKit
import Carbon

struct ShortcutBinding: Codable, Equatable, Identifiable {
    var id: UInt32
    var key: UInt32
    var modifiers: UInt32
    var enabled: Bool = true
    static let defaults = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 38].enumerated().map {
        Self(id: UInt32($0.offset + 1), key: UInt32($0.element), modifiers: UInt32(controlKey | optionKey), enabled: $0.offset < 3)
    }
    var title: String {
        switch id {
        case 1: "后台工作"; case 2: "桌面工作"; case 3: "正常休眠"
        case 4: "开始 / 结束会话"; case 5: "允许 / 阻止显示器休眠"
        case 6: "允许 / 阻止屏保"; case 7: "开启 / 关闭合盖运行"
        case 8: "延长会话 15 分钟"; case 9: "打开菜单栏面板"
        case 10: "开始默认时长会话"; case 11: "开始无限期会话"; default: "未知操作"
        }
    }
    enum CodingKeys: String, CodingKey { case id, key, modifiers, enabled }
    init(id: UInt32, key: UInt32, modifiers: UInt32, enabled: Bool = true) {
        self.id = id; self.key = key; self.modifiers = modifiers; self.enabled = enabled
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UInt32.self, forKey: .id); key = try values.decode(UInt32.self, forKey: .key)
        modifiers = try values.decode(UInt32.self, forKey: .modifiers)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
    static func migrated(_ saved: [Self]) -> [Self] {
        defaults.map { original in saved.first(where: { $0.id == original.id }) ?? original }
    }
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
    static let modifiers: [(String, UInt32)] = [("⌃⌥", UInt32(controlKey | optionKey)), ("⌃⌥⌘", UInt32(controlKey | optionKey | cmdKey)), ("⌘⇧", UInt32(cmdKey | shiftKey)), ("⌃⇧", UInt32(controlKey | shiftKey)), ("⌥⇧", UInt32(optionKey | shiftKey)), ("⌃⌘", UInt32(controlKey | cmdKey)), ("⌥⌘", UInt32(optionKey | cmdKey)), ("⌃⌥⇧⌘", UInt32(controlKey | optionKey | shiftKey | cmdKey))]
    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        if let data = preferences.data(forKey: "Shortcuts"), let saved = try? JSONDecoder().decode([ShortcutBinding].self, from: data) { bindings = ShortcutBinding.migrated(saved) }
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
        for value in values where value.enabled {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(value.key, value.modifiers, EventHotKeyID(signature: 0x574D4F44, id: value.id), GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else { return "\(value.title)快捷键被占用或不可用（\(status)），请更换。" }
            refs.append(ref)
        }
        return nil
    }
    func apply(_ values: [ShortcutBinding], enabled newEnabled: Bool) {
        guard values.map(\.id) == ShortcutBinding.defaults.map(\.id) else { message = "快捷键操作列表无效。"; return }
        let active = values.filter(\.enabled)
        guard Set(active.map { "\($0.key):\($0.modifiers)" }).count == active.count else { message = "已启用的操作不能使用相同快捷键。"; return }
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
