import Foundation
import Darwin
public enum CommandRunner {
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) throws -> String {
        // A private temporary file avoids pipe-buffer deadlocks without retaining diagnostics.
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("workmodes-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw ModeError("无法创建命令输出缓冲。")
        }
        defer { try? FileManager.default.removeItem(at: output) }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            let grace = Date().addingTimeInterval(0.3)
            while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw ModeError("操作超时：" + URL(fileURLWithPath: executable).lastPathComponent)
        }
        process.waitUntilExit()
        let reader = try FileHandle(forReadingFrom: output)
        defer { try? reader.close() }
        let data = try reader.read(upToCount: 65536) ?? Data()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw ModeError("\(URL(fileURLWithPath: executable).lastPathComponent) 执行失败（\(process.terminationStatus)）：\n\(text)")
        }
        return text
    }
}
