#if os(macOS)
import CryptoKit
import Foundation
import Security

enum MacMailKeychain {
    static func perform(_ request: MailKeychainMessage) throws -> MailKeychainReply {
        guard let executable = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("CardPilotMailKeychain"), FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw PilotError.invalid("邮箱连接组件缺失，请重新构建并打开 CardPilot。")
        }
        try validate(executable)
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(request))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, data.count <= 16_384,
              let result = try? JSONDecoder().decode(MailKeychainReply.self, from: data) else {
            throw PilotError.invalid("暂时无法连接邮箱安全组件，请重新打开 App 后重试。")
        }
        if result.status == -70001 { throw PilotError.invalid("邮箱组件未能验证 CardPilot 身份，请通过项目启动脚本重新构建。") }
        return result
    }

    private static func validate(_ executable: URL) throws {
        let flags = SecCSFlags(rawValue: 0)
        var own: SecCode?, ownStatic: SecStaticCode?, helper: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf(flags, &own) == errSecSuccess, let own,
              SecCodeCopyStaticCode(own, flags, &ownStatic) == errSecSuccess, let ownStatic,
              SecCodeCopySigningInformation(ownStatic, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let certificates = (info as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { throw PilotError.invalid("暂时无法验证 CardPilot 签名，请重新打开 App。") }
        let digest = Insecure.SHA1.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
        let text = "identifier \"com.cardpilot.mail-keychain\" and certificate leaf = H\"\(digest)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, flags, &requirement) == errSecSuccess,
              let requirement, SecStaticCodeCreateWithPath(executable as CFURL, flags, &helper) == errSecSuccess,
              let helper, SecStaticCodeCheckValidity(helper, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw PilotError.invalid("邮箱组件签名与 CardPilot 不一致，请重新构建 App。")
        }
    }
}
#endif
