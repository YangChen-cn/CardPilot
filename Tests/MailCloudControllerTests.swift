import Foundation
import SwiftData
import Testing
@testable import CardPilot

@Suite @MainActor
struct MailCloudControllerTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "CardPilotTests.MailCloud." + UUID().uuidString)!
    }

    @Test func initializationDoesNotReadCredentials() {
        let preferences = defaults()
        var reads = 0
        let cloud = MailCloudController(defaults: preferences, allowsSync: true) {
            reads += 1
            return nil
        }
        #expect(reads == 0)
        #expect(!cloud.isConnected)
        #expect(!cloud.isSyncing)
    }

    @Test(arguments: [false, true])
    func discoversConnectionWithoutImportWhenDisabledOrAlreadyCurrent(automatic: Bool) async throws {
        let preferences = defaults()
        preferences.set(automatic, forKey: "mail.cloud.automatic")
        preferences.set(Date.now, forKey: "mail.cloud.lastSync")
        let container = try Persistence.makeContainer(inMemory: true)
        var reads = 0
        let cloud = MailCloudController(defaults: preferences, allowsSync: true) {
            reads += 1
            // No request is made: import is disabled or already current today.
            return MailCloudConnection(url: "https://script.google.com/macros/s/test-only/exec",
                                       token: String(repeating: "x", count: 96))
        }
        await cloud.sync(in: container.mainContext)
        #expect(reads == 1)
        #expect(cloud.isConnected)
        #expect(!cloud.isSyncing)
        #expect(cloud.error == nil)
    }

    @Test func concurrentStartupCallsOnlyReadCredentialsOnce() async throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let entered = AsyncStream<Void>.makeStream()
        var completion: CheckedContinuation<MailCloudConnection?, Never>?
        var reads = 0
        let cloud = MailCloudController(defaults: defaults(), allowsSync: true) {
            reads += 1
            entered.continuation.yield(())
            return await withCheckedContinuation { completion = $0 }
        }
        let first = Task { await cloud.sync(in: container.mainContext) }
        var iterator = entered.stream.makeAsyncIterator()
        _ = await iterator.next()
        await cloud.sync(in: container.mainContext)
        #expect(reads == 1)
        #expect(cloud.isSyncing)
        completion?.resume(returning: nil)
        await first.value
        entered.continuation.finish()
        #expect(!cloud.isSyncing)
        #expect(!cloud.isConnected)
    }

    @Test func readFailureIsReportedAndDoesNotPreventRetry() async throws {
        let container = try Persistence.makeContainer(inMemory: true)
        var attempts = 0
        let cloud = MailCloudController(defaults: defaults(), allowsSync: true) {
            attempts += 1
            if attempts == 1 { throw PilotError.invalid("Test credential read failed") }
            return nil
        }
        await cloud.sync(in: container.mainContext)
        #expect(cloud.error == "Test credential read failed")
        #expect(!cloud.isSyncing)
        await cloud.sync(in: container.mainContext)
        #expect(cloud.error == nil)
        #expect(!cloud.isSyncing)
    }
}
