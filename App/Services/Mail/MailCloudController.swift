import CryptoKit
import Foundation
import Observation
import SwiftData

@MainActor @Observable final class MailCloudController {
    static let shared = MailCloudController()
    private(set) var isConnected = false
    private(set) var isSyncing = false
    private(set) var lastSyncAt: Date?
    private(set) var message: String?
    private(set) var error: String?
    private let defaults: UserDefaults
    private let allowsSync: Bool
    private let loadConnection: @MainActor () async throws -> MailCloudConnection?
    var automatic: Bool {
        didSet { defaults.set(automatic, forKey: "mail.cloud.automatic") }
    }

    init(defaults: UserDefaults = .standard,
         allowsSync: Bool = !RuntimeMode.isEphemeral,
         loadConnection: @escaping @MainActor () async throws -> MailCloudConnection? = {
             try MailCloudConnectionStore.load()
         }) {
        self.defaults = defaults
        self.allowsSync = allowsSync
        self.loadConnection = loadConnection
        automatic = defaults.object(forKey: "mail.cloud.automatic") as? Bool ?? true
        if allowsSync {
            lastSyncAt = defaults.object(forKey: "mail.cloud.lastSync") as? Date
        }
        // Never invoke the Keychain helper while static `shared` is initializing.
        // Its process I/O can reenter the run loop and access `shared` again.
    }

    func connect(url: String, token: String, in context: ModelContext) async {
        do {
            let connection = MailCloudConnection(url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                                                 token: token.trimmingCharacters(in: .whitespacesAndNewlines))
            try MailCloudConnectionStore.save(connection)
            isConnected = true; error = nil; message = nil; lastSyncAt = nil
            defaults.removeObject(forKey: "mail.cloud.lastSync")
            await sync(in: context, force: true)
        } catch { self.error = PilotError.message(error) }
    }

    func disconnect() {
        guard !isSyncing else { return }
        do { try MailCloudConnectionStore.remove(); isConnected = false; error = nil; message = nil }
        catch { self.error = PilotError.message(error) }
    }

    func sync(in context: ModelContext, force: Bool = false) async {
        guard allowsSync, !isSyncing else { return }
        // Set the guard before any credential I/O or suspension. Launch and
        // scene-activation tasks may arrive together or reenter during the read.
        isSyncing = true; error = nil
        defer { isSyncing = false }
        do {
            guard let connection = try await loadConnection() else { isConnected = false; return }
            isConnected = true
            guard force || automatic else { return }
            if !force, let lastSyncAt, HKCalendar.calendar.isDate(lastSyncAt, inSameDayAs: .now) { return }
            let url = try connection.validatedURL()
            let digest = SHA256.hash(data: Data(connection.url.utf8)).map { String(format: "%02x", $0) }.joined()
            let key = "mail.cloud.cursor." + digest
            var cursor = defaults.string(forKey: key)
            let retried = try MailImportService.retryPending(in: context)
            var saved = retried.saved, updated = retried.updated, pending = retried.pending
            for _ in 0..<20 {
                let data = try await download(connection: connection, url: url, cursor: cursor)
                let transactions = try await Task.detached(priority: .utility) { try BankMailParser.decodePackage(data) }.value
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let next = object?["nextCursor"] as? String
                let count = (object?["messages"] as? [Any])?.count ?? 0
                if count == 0 {
                    lastSyncAt = .now; defaults.set(lastSyncAt, forKey: "mail.cloud.lastSync")
                    message = "新增 \(saved) 笔，校正 \(updated) 笔，待核对 \(pending) 笔。"
                    return
                }
                guard let next, !next.isEmpty, next.count <= 1000, next != cursor else {
                    throw PilotError.invalid("云端资料暂时无法继续读取，已导入的记录会保留。")
                }
                let result = try MailImportService.importTransactions(transactions, in: context)
                saved += result.saved; updated += result.updated; pending += result.pending
                // Advance only after the corresponding page is committed. Replays remain idempotent.
                defaults.set(next, forKey: key); cursor = next
            }
            message = "本批邮件已保存，请再点一次更新以继续导入。"
        } catch {
            self.error = PilotError.message(error, fallback: "暂时无法读取云端邮件，请检查连接后重试。")
        }
    }

    private nonisolated func download(connection: MailCloudConnection, url: URL, cursor: String?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 40
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = ["token": connection.token]
        if let cursor { body["after"] = cursor }
        request.httpBody = try JSONEncoder().encode(body)
        let session = URLSession(configuration: .ephemeral, delegate: MailCloudRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.scheme == "https", response.expectedContentLength <= 5_000_000,
              ["script.google.com", "script.googleusercontent.com"].contains(response.url?.host ?? "") else {
            throw PilotError.invalid("云端服务未返回交易资料，请检查部署网址和访问设置。")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 5_000_000 else { throw PilotError.invalid("这批邮件资料过大，请分批导入。") }
            data.append(byte)
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["error"] != nil {
            throw PilotError.invalid("云端连接未获准或资料尚未准备好，请检查连接码与云端运行状态。")
        }
        return data
    }
}

private final class MailCloudRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard request.url?.scheme == "https",
              ["script.google.com", "script.googleusercontent.com"].contains(request.url?.host ?? ""),
              request.httpMethod == "GET", request.httpBody == nil else { return nil }
        return request
    }
}
