// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import Foundation

public struct CommandJobResult: Sendable {
    public let exitCode: Int32
    public let logURL: URL
    public let truncated: Bool
}
public enum CommandJob {
    /// Runs only the explicitly submitted foreground shell; stdin is closed (noninteractive).
    public static func run(command: String, directory: String, logURL: URL, logLimit: Int = 5 * 1024 * 1024) throws -> CommandJobResult {
        var isDirectory: ObjCBool = false
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ModeError("命令不能为空，工作目录必须存在。")
        }
        guard FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw ModeError("无法创建任务日志。") }
        let output = try FileHandle(forWritingTo: logURL)
        defer { try? output.close() }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        try? pipe.fileHandleForWriting.close()
        var written = 0, truncated = false
        while let data = try pipe.fileHandleForReading.read(upToCount: 8192), !data.isEmpty {
            let keep = max(0, min(data.count, logLimit - written))
            if keep > 0 { try output.write(contentsOf: data.prefix(keep)); written += keep }
            if keep < data.count { truncated = true }
        }
        try? pipe.fileHandleForReading.close()
        process.waitUntilExit()
        return CommandJobResult(exitCode: process.terminationReason == .exit ? process.terminationStatus : -process.terminationStatus, logURL: logURL, truncated: truncated)
    }
}
