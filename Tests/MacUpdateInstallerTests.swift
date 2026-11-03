#if os(macOS)
import Foundation
import Testing
@testable import CardPilot

@Suite struct MacUpdateInstallerTests {
    private func prepare() throws -> (URL, MacUpdateInstaller.Prepared) {
        let root = URL.temporaryDirectory.appendingPathComponent("CardPilot-install-test-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let prepared = MacUpdateInstaller.Prepared(target: root.appendingPathComponent("old.app"), staging: root.appendingPathComponent("new.app"), backup: root.appendingPathComponent("backup.app"))
        try Data("old".utf8).write(to: prepared.target)
        try Data("new".utf8).write(to: prepared.staging)
        return (root, prepared)
    }

    @Test func failedReplacementRestoresOriginalAndKeepsStaging() throws {
        let (root, prepared) = try prepare()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: CocoaError.self) {
            try MacUpdateInstaller.replace(prepared) { source, destination in
                if source == prepared.staging { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.moveItem(at: source, to: destination)
            }
        }
        #expect(try String(contentsOf: prepared.target, encoding: .utf8) == "old")
        #expect(try String(contentsOf: prepared.staging, encoding: .utf8) == "new")
        #expect(!FileManager.default.fileExists(atPath: prepared.backup.path))
    }

    @Test func replacementKeepsBackupAndRollbackRestoresIt() async throws {
        let (root, prepared) = try prepare()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = MacUpdateInstaller()
        try await installer.replace(prepared)
        #expect(try String(contentsOf: prepared.backup, encoding: .utf8) == "old")
        #expect(try String(contentsOf: prepared.target, encoding: .utf8) == "new")
        try await installer.rollback(prepared)
        #expect(try String(contentsOf: prepared.target, encoding: .utf8) == "old")
        #expect(try String(contentsOf: prepared.staging, encoding: .utf8) == "new")
    }

    @Test func launchMarkerIsConfinedToTheSpecificCacheAndWaitsForConfirmation() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent("CardPilot-marker-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent(UUID().uuidString, isDirectory: true).appendingPathComponent(LaunchConfirmation.markerFileName)
        #expect(!(await MacUpdateInstaller.waitForLaunchMarker(at: marker, timeout: .milliseconds(40), poll: .milliseconds(5))))
        #expect(!LaunchConfirmation.confirmIfRequested(arguments: ["App", "--launch-marker", root.appendingPathComponent("outside.marker").path], cacheDirectory: root))
        #expect(LaunchConfirmation.confirmIfRequested(arguments: ["App", "--launch-marker", marker.path], cacheDirectory: root))
        #expect(await MacUpdateInstaller.waitForLaunchMarker(at: marker, timeout: .milliseconds(40)))
    }

    @Test func embeddedUpdaterHasTheSameCertificateAndExpectedIdentity() throws {
        let app = Bundle.main.bundleURL
        let certificate = try UpdateSigning.certificate(of: app, identifier: "com.cardpilot.app.mac")
        let helper = app.appendingPathComponent("Contents/Helpers/CardPilotUpdater.app")
        #expect(try UpdateSigning.certificate(of: helper, identifier: "com.cardpilot.updater") == certificate)
        #expect(throws: (any Error).self) { try UpdateSigning.certificate(of: helper, identifier: "com.other.helper") }
    }
}
#endif
