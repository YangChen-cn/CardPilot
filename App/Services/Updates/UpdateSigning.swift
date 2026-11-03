#if os(macOS)
import Foundation
import Security

enum UpdateSigning {
    static func certificate(of url: URL, identifier: String) throws -> Data {
        var code: SecStaticCode?, info: CFDictionary?
        let flags = SecCSFlags(rawValue: 0)
        guard SecStaticCodeCreateWithPath(url as CFURL, flags, &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any], values[kSecCodeInfoIdentifier as String] as? String == identifier,
              let certificates = values[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { throw MacUpdateInstaller.Failure.invalidPackage }
        return SecCertificateCopyData(leaf) as Data
    }
}
#endif
