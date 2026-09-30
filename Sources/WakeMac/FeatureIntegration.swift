// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import Foundation
import WakeMacCore

extension AppModel {
    func handleSystemWillSleep() async {
        // A closed-lid power transition can emit willSleep. It does not identify
        // a user's explicit Sleep action and must not revoke background work.
        guard !busy, active != .background, snapshot?.backgroundLeaseActive != true else { return }
        if sessions.isActive { await sessions.end() }
        else if keepsAwake, triggerOwnedMode == nil { await choose(.normal) }
    }
    func makeSessionController() -> SessionController {
        let controller = SessionController(preferences: preferences, effects: sessionEffects)
        controller.workingProvider = { [weak self] in self?.verifiedWork == true }
        controller.onBegin = { [weak self] mode in
            guard let self, !self.busy else { return false }
            self.suppressCurrentTriggers()
            self.sessions.effectOverrides = nil
            await self.choose(mode, automatic: true)
            let verified = self.active == mode && !self.error && self.pending == nil
            if verified { self.featureNotificationHandler?("工作会话已开始：" + mode.title, .sessionStart) }
            return verified
        }
        controller.onEnd = { [weak self] in
            guard let self else { return }
            await self.choose(.normal, automatic: true)
            if self.active == .normal, !self.error, self.pending == nil {
                self.featureNotificationHandler?("工作会话已结束，已恢复正常休眠。", .sessionEnd)
            }
        }
        controller.onExtended = { [weak self] minutes in
            guard let self else { return }
            let text = "工作会话已延长 \(minutes.formatted()) 分钟。"
            self.record(text)
            self.featureNotificationHandler?(text, .sessionExtended)
            self.onUpdate?()
        }
        return controller
    }
    func suppressCurrentTriggers() {
        suppressedTriggerIDs.formUnion(triggers.rules.filter(\.enabled).map(\.id))
        triggerOwnedMode = nil
        triggerOwnedRuleID = nil; appliedTriggerBehavior = nil
        triggerRuntimeMode = nil
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
            if triggerOwnedRuleID != desired.id { triggerRuntimeMode = nil }
            let targetMode = triggerRuntimeMode ?? desired.mode
            if triggerOwnedMode != targetMode || active != targetMode {
                await choose(targetMode, automatic: true)
                guard active == targetMode, !error, pending == nil else {
                    suppressedTriggerIDs.formUnion(available.map(\.id)); return
                }
                triggerOwnedMode = targetMode
                record("自动触发：" + available.map(\.name).joined(separator: "、"))
            }
            let behavior = SessionBehaviorOverride(display: desired.preventDisplaySleep, saver: desired.preventScreenSaver)
            if triggerOwnedRuleID != desired.id || appliedTriggerBehavior != behavior {
                triggerOwnedRuleID = desired.id; appliedTriggerBehavior = behavior
                sessions.effectOverrides = behavior
                await sessions.tick(now: date)
                featureNotificationHandler?("自动触发：" + desired.name, .triggerChange)
            }
            triggerSummary = "自动触发：" + available.map(\.name).joined(separator: "、")
        } else if triggerOwnedMode != nil {
            // A rule naturally ending is not a manual veto. It may run again
            // when its conditions next become true.
            await choose(.normal, automatic: true, startupRecovery: true)
            triggerOwnedMode = nil; triggerOwnedRuleID = nil; appliedTriggerBehavior = nil
            triggerRuntimeMode = nil
            triggerSummary = "规则条件已解除，恢复正常休眠"
            featureNotificationHandler?(triggerSummary, .triggerChange)
        } else { triggerSummary = matching.isEmpty ? triggers.status : "手动操作优先；等待规则条件解除" }
    }
}
