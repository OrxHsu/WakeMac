import AppKit
import WakeMacCore

@MainActor enum ScriptBridge { static weak var model: AppModel? }

struct ScriptSessionArguments {
    let mode: WorkMode
    let minutes: Double?
    init(_ args: [String: Any]) throws {
        let raw = args["mode"] as? String ?? "desktop"
        switch raw { case "desktop": mode = .desk; case "background": mode = .background; default: throw ModeError("mode 必须为 desktop 或 background。") }
        if let value = args["minutes"] {
            guard let number = value as? NSNumber, number.doubleValue.isFinite, (1...10080).contains(number.doubleValue) else { throw ModeError("for minutes 必须为 1–10080 分钟。") }
            minutes = number.doubleValue
        } else { minutes = nil }
    }
}

@objc(WakeMacStartSessionCommand) final class StartSessionCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let arguments: ScriptSessionArguments
        do { arguments = try ScriptSessionArguments(evaluatedArguments ?? [:]) }
        catch { scriptErrorNumber = -1700; scriptErrorString = error.localizedDescription; return nil }
        suspendExecution()
        Task { @MainActor in
            guard let model = ScriptBridge.model, !model.busy, !model.sessions.isStarting else {
                scriptErrorNumber = -1712; scriptErrorString = "WakeMac 正忙，请稍后重试。"; resumeExecution(withResult: nil); return
            }
            if model.sessions.isActive { await model.sessions.end() }
            model.sessions.defaultMode = arguments.mode
            if let minutes = arguments.minutes { model.sessions.endCondition = .duration; model.sessions.durationMinutes = minutes }
            else { model.sessions.endCondition = .indefinite }
            await model.sessions.start()
            if !model.sessions.isActive { scriptErrorNumber = -10000; scriptErrorString = model.sessions.status }
            resumeExecution(withResult: model.sessions.status)
        }
        return nil
    }
}
@objc(WakeMacEndSessionCommand) final class EndSessionCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        suspendExecution()
        Task { @MainActor in
            guard let model = ScriptBridge.model, !model.busy else { scriptErrorNumber = -1712; scriptErrorString = "WakeMac 正忙。"; resumeExecution(withResult: nil); return }
            await model.choose(.normal)
            if model.error || model.pending != nil { scriptErrorNumber = -10000; scriptErrorString = model.message }
            resumeExecution(withResult: model.headline)
        }
        return nil
    }
}
@objc(WakeMacSessionStatusCommand) final class SessionStatusCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        suspendExecution()
        Task { @MainActor in resumeExecution(withResult: ScriptBridge.model?.headline ?? "WakeMac 不可用") }
        return nil
    }
}
