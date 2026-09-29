import Foundation
import WakeMacCore

extension AppModel {
    func makeSessionController() -> SessionController {
        let controller = SessionController(preferences: preferences, effects: sessionEffects)
        controller.workingProvider = { [weak self] in self?.keepsAwake == true && self?.snapshot?.lockPolicy == .immediate }
        controller.onBegin = { [weak self] mode in
            guard let self, !self.busy else { return false }
            self.suppressCurrentTriggers()
            await self.choose(mode, automatic: true)
            return self.active == mode && !self.error && self.pending == nil
        }
        controller.onEnd = { [weak self] in await self?.choose(.normal, automatic: true) }
        return controller
    }
    func suppressCurrentTriggers() {
        suppressedTriggerIDs.formUnion(triggers.rules.filter(\.enabled).map(\.id))
        triggerOwnedMode = nil
        triggerSummary = "手动操作优先；当前规则解除后可再次触发"
    }
    func tickFeatures(now date: Date, battery reading: BatteryReading?) async {
        guard !featureTickRunning else { return }
        featureTickRunning = true
        defer { featureTickRunning = false }
        await sessions.tick(now: date)
        await idlePolicy.tick()
        guard !busy, pending == nil, date.timeIntervalSince(lastFeatureSample) >= 5 else { return }
        lastFeatureSample = date
        let revision = generation
        let matching = await triggers.matchingRules(now: date, battery: reading)
        guard generation == revision, !busy, pending == nil else { return }
        suppressedTriggerIDs.formIntersection(Set(matching.map(\.id)))
        guard !sessions.isActive, !sessions.isStarting else { triggerSummary = "当前会话优先于自动触发"; return }
        let available = matching.filter { !suppressedTriggerIDs.contains($0.id) }
        if let desired = available.first(where: { $0.mode == .background }) ?? available.first {
            if triggerOwnedMode == nil && active != .normal { triggerSummary = "保留当前手动工作模式"; return }
            if triggerOwnedMode != desired.mode || active != desired.mode {
                await choose(desired.mode, automatic: true)
                guard active == desired.mode, !error, pending == nil else {
                    suppressedTriggerIDs.formUnion(available.map(\.id)); return
                }
                triggerOwnedMode = desired.mode
                record("自动触发：" + available.map(\.name).joined(separator: "、"))
            }
            triggerSummary = "自动触发：" + available.map(\.name).joined(separator: "、")
        } else if triggerOwnedMode != nil {
            await choose(.normal, automatic: true)
            triggerSummary = "规则条件已解除，恢复正常休眠"
        } else { triggerSummary = matching.isEmpty ? triggers.status : "手动操作优先；等待规则条件解除" }
    }
}
