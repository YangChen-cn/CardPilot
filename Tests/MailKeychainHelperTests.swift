#if os(macOS)
import Foundation
import Security
import Testing
@testable import CardPilot

@Suite @MainActor struct MailKeychainHelperTests {
    @Test func sameCertificateAppCanUseTheTransportWithoutReadingCredentials() throws {
        let reply = try MacMailKeychain.perform(MailKeychainMessage(operation: .probe))
        #expect(reply.status == errSecSuccess)
        #expect(reply.data == nil)
        let url = try #require(Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("CardPilotMailKeychain"))
        var code: SecStaticCode?, info: CFDictionary?
        #expect(SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(rawValue: 0), &code) == errSecSuccess)
        let signedCode = try #require(code)
        #expect(SecCodeCopySigningInformation(signedCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess)
        let digest = try #require((info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data)
        #expect(reply.codeHash == digest.map { String(format: "%02x", $0) }.joined())
    }

    @Test func unrelatedShellCannotUseTheHelper() throws {
        let url = try #require(Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("CardPilotMailKeychain"))
        let process = Process(), output = Pipe(), input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "\"$1\"; exit 0", "helper-test", url.path]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(MailKeychainMessage(operation: .probe)))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let reply = try JSONDecoder().decode(MailKeychainReply.self, from: data)
        #expect(reply.status == -70001)
        #expect(reply.data == nil)
    }
}
#endif
