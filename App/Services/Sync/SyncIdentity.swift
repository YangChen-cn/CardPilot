import Foundation
import CryptoKit

enum SyncIdentity {
    static func id(for key: String) -> UUID {
        if let id = UUID(uuidString: String(key.suffix(36))) { return id }
        let bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

extension BankCard {
    var syncKey: String { "card:" + (catalogID.isEmpty ? id.uuidString : "catalog:" + catalogID) }

    /// Cross-device key for personal offer overlays. Official cards are matched
    /// by their catalog identity during sync, so this is the stable card key.
    /// The current app allows one held instance per official product; if that
    /// changes, an explicit synced instance identifier can be added here without
    /// changing existing keys.
    var overlayKey: String { syncKey }
}

extension RewardRule {
    var syncKey: String { "rule:" + (externalID.isEmpty ? id.uuidString : (card?.syncKey ?? "") + ":" + externalID) }
}

extension SpendTransaction {
    var syncKey: String { "transaction:" + (["shortcuts", "csv", "email", "sms"].contains(source) && !externalID.isEmpty ? (card?.syncKey ?? "") + ":" + externalID : id.uuidString) }
}
