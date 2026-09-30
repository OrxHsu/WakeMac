// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import Foundation
import Security

@objc public protocol PowerServiceProtocol {
    func setBackground(_ enabled: Bool, reply: @escaping (String?) -> Void)
    func renew(reply: @escaping (String?) -> Void)
}

public enum PowerService {
    public static let appIdentifier = "local.orx.WorkModes" // Stable installed-app identity.
    public static let identifier = "local.orx.WakeMac.PowerHelper"
    public static let plistName = identifier + ".plist"
    /// Require an Apple-issued signing identity shared with this executable.
    /// Unsigned/ad hoc builds can use desktop mode, but cannot run a root service.
    public static func peerRequirement(identifier: String) throws -> String {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { throw signingError }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { throw signingError }
        var raw: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &raw) == errSecSuccess,
              let info = raw as? [String: Any], let team = info[kSecCodeInfoTeamIdentifier as String] as? String,
              team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else { throw signingError }
        let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and identifier \"\(identifier)\""
        var parsed: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess else { throw signingError }
        return requirement
    }
    private static var signingError: NSError {
        NSError(domain: "WakeMacSigning", code: 1, userInfo: [NSLocalizedDescriptionKey: "合盖服务需要使用同一 Apple 开发者证书签名。当前构建仍可使用桌面工作与正常休眠。"])
    }
}
