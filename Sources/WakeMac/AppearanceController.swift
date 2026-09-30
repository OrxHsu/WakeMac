// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import AppKit
import AVFoundation
import Combine
import UserNotifications

@MainActor final class AppearanceController: ObservableObject {
    enum Icon: String, CaseIterable, Identifiable {
        case moon, cup, bolt, custom
        var id: String { rawValue }
        var title: String { switch self { case .moon: "折月"; case .cup: "咖啡杯"; case .bolt: "闪电"; case .custom: "自定义" } }
    }
    @Published var icon: Icon { didSet { preferences.set(icon.rawValue, forKey: "appearance.icon"); onUpdate?() } }
    @Published var template: Bool { didSet { preferences.set(template, forKey: "appearance.template"); onUpdate?() } }
    @Published var showEndTime: Bool { didSet { preferences.set(showEndTime, forKey: "appearance.showEndTime"); onUpdate?() } }
    @Published var twentyFourHour: Bool { didSet { preferences.set(twentyFourHour, forKey: "appearance.24hour"); onUpdate?() } }
    @Published var iconPadding: Double { didSet { preferences.set(iconPadding, forKey: "appearance.padding"); onUpdate?() } }
    @Published private(set) var soundName: String
    @Published private(set) var message = ""
    var onUpdate: (() -> Void)?
    private let preferences: UserDefaults
    init(preferences: UserDefaults) {
        self.preferences = preferences
        icon = Icon(rawValue: preferences.string(forKey: "appearance.icon") ?? "moon") ?? .moon
        template = preferences.object(forKey: "appearance.template") as? Bool ?? true
        showEndTime = preferences.bool(forKey: "appearance.showEndTime")
        twentyFourHour = preferences.object(forKey: "appearance.24hour") as? Bool ?? true
        soundName = preferences.string(forKey: "appearance.sound") ?? ""
        iconPadding = preferences.object(forKey: "appearance.padding") as? Double ?? 0
    }
    func menuImage() -> NSImage {
        let source = baseMenuImage()
        let padding = iconPadding.isFinite ? min(max(iconPadding, 0), 12) : 0
        guard padding > 0 else { return source }
        let image = NSImage(size: NSSize(width: 20 + padding * 2, height: 18), flipped: false) { _ in
            source.draw(in: NSRect(x: padding, y: 0, width: 20, height: 18)); return true
        }
        image.isTemplate = source.isTemplate; return image
    }
    private func baseMenuImage() -> NSImage {
        if icon == .moon { return MenuMark.image() }
        if icon == .custom, let path = preferences.string(forKey: "appearance.customIcon"), let original = NSImage(contentsOfFile: path), original.size.width > 0, original.size.height > 0 {
            let bounds = NSSize(width: 20, height: 18)
            let scale = min(bounds.width / original.size.width, bounds.height / original.size.height)
            let size = NSSize(width: original.size.width * scale, height: original.size.height * scale)
            let image = NSImage(size: bounds, flipped: false) { rect in
                original.draw(in: NSRect(x: (rect.width-size.width)/2, y: (rect.height-size.height)/2, width: size.width, height: size.height))
                return true
            }
            image.isTemplate = template; return image
        }
        let image = NSImage(systemSymbolName: icon == .cup ? "cup.and.saucer.fill" : "bolt.fill", accessibilityDescription: "WakeMac") ?? MenuMark.image()
        image.isTemplate = true; image.size = NSSize(width: 20, height: 18); return image
    }
    func chooseIcon() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.png, .jpeg, .tiff, .icns]
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do {
            let attrs = try file.resourceValues(forKeys: [.fileSizeKey]); guard (attrs.fileSize ?? .max) <= 5_000_000, NSImage(contentsOf: file) != nil else { throw ImportError.invalidImage }
            let folder = AppPaths.root.appendingPathComponent("Menu Icons", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent(UUID().uuidString + "." + file.pathExtension)
            try FileManager.default.copyItem(at: file, to: target)
            preferences.set(target.path, forKey: "appearance.customIcon"); icon = .custom; message = "菜单栏图标已更新。"
        } catch { message = error.localizedDescription }
    }
    func chooseSound() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let file = panel.url else { return }
        Task { await importSound(file) }
    }
    func importSound(_ file: URL) async {
        do {
            guard ["aiff", "aif", "wav", "caf"].contains(file.pathExtension.lowercased()) else { throw ImportError.invalidSound }
            let duration = try await AVURLAsset(url: file).load(.duration).seconds
            guard duration.isFinite, duration > 0, duration < 30 else { throw ImportError.invalidSound }
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = "WakeMac-" + UUID().uuidString + "." + file.pathExtension
            try FileManager.default.copyItem(at: file, to: folder.appendingPathComponent(name))
            soundName = name; preferences.set(name, forKey: "appearance.sound"); message = "通知声音已更新。"
        } catch { message = error.localizedDescription }
    }
    func resetSound() { soundName = ""; preferences.removeObject(forKey: "appearance.sound"); message = "已恢复系统通知声音。" }
    func previewSound() {
        guard !soundName.isEmpty else { NSSound.beep(); return }
        NSSound(contentsOfFile: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds/" + soundName).path, byReference: true)?.play()
    }
    private var lidSound: NSSound?
    func playLidTone(volume: Double) {
        guard volume.isFinite, lidSound?.isPlaying != true else { return }
        let sound = soundName.isEmpty ? NSSound(named: NSSound.Name("Glass")) : NSSound(contentsOfFile: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds/" + soundName).path, byReference: true)
        sound?.volume = Float(min(max(volume, 0), 1)); lidSound = sound; sound?.play()
    }
    private enum ImportError: LocalizedError {
        case invalidImage, invalidSound
        var errorDescription: String? {
            switch self { case .invalidImage: "请选择小于 5 MB 的有效图片。"; case .invalidSound: "请选择短于 30 秒的 AIFF、WAV 或 CAF 音频。" }
        }
    }
}
