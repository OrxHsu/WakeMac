import Foundation
public enum SystemParsing {
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
}
