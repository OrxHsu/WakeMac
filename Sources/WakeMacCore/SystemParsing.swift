import Foundation
public enum SystemParsing {
    public static func sessionDuration(_ text: String) throws -> Int {
        let fields = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ",")
        guard fields.count == 6, let duration = Int(fields[5].trimmingCharacters(in: .whitespaces)), duration >= -3 else {
            throw ModeError("无法核验 Amphetamine 会话时长。")
        }
        return duration
    }
    public static func sleepDisabled(_ text: String) -> Bool? {
        for line in text.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            if fields.first == "SleepDisabled", fields.count == 2 {
                if fields[1] == "1" { return true }
                if fields[1] == "0" { return false }
            }
        }
        return nil
    }
    public static func lockPolicy(_ text: String) -> LockPolicy {
        if text.contains("screenLock is off") { return .off }
        if text.contains("screenLock delay is immediate") { return .immediate }
        if text.range(of: #"screenLock delay is [0-9]+ seconds"#, options: .regularExpression) != nil { return .delayed }
        return .unknown
    }
    public static func amphetamine(_ text: String) throws -> [Bool] {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 5, parts.allSatisfy({ $0 == "true" || $0 == "false" }) else {
            throw ModeError("Amphetamine 返回了无法识别的状态。")
        }
        return parts.map { $0 == "true" }
    }
}
