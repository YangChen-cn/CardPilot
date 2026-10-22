import Foundation

/// Deterministic projection shared by local imports and folder sync. Email owns financial
/// facts; personal classification and fields absent from the email remain on the ledger.
enum MailReconciliation {
    private struct Receipt {
        var record: SyncRecord
        var document: DocumentSyncData
        var evidence: MailEvidence
    }

    static func project(_ input: [String: SyncRecord]) -> [String: SyncRecord] {
        var records = input
        let decoder = SyncCodec.decoder(), encoder = SyncCodec.encoder()
        let receipts: [Receipt] = records.values.compactMap { record in
            guard record.kind == "document", !record.deleted,
                  let document = try? decoder.decode(DocumentSyncData.self, from: record.payload ?? Data()),
                  document.kind == "mailEvidence", !document.isDeleted,
                  let evidence = try? decoder.decode(MailEvidence.self, from: document.content),
                  MailEvidence.valid(evidence.mail) else { return nil }
            return Receipt(record: record, document: document, evidence: evidence)
        }
        let groups = Dictionary(grouping: receipts, by: { $0.evidence.transactionKey })
        var chosen: [String: Receipt] = [:]
        var claimed = Set(receipts.flatMap { $0.evidence.aliases })
        for (key, group) in groups {
            chosen[key] = group.sorted {
                if $0.evidence.mail.source != $1.evidence.mail.source { return $0.evidence.mail.source == "email" }
                if $0.evidence.mail.receivedAt != $1.evidence.mail.receivedAt { return $0.evidence.mail.receivedAt > $1.evidence.mail.receivedAt }
                if $0.record.revisionMillis != $1.record.revisionMillis { return $0.record.revisionMillis > $1.record.revisionMillis }
                return $0.record.key < $1.record.key
            }.first
        }
        // Compute all candidates first. A date-only email cannot consume two same-day
        // purchases, and two emails cannot both consume the same Wallet transaction.
        var candidates: [String: [String]] = [:]
        var suspected: [String: [String]] = [:]
        for (key, receipt) in chosen where records[key]?.deleted != true {
            let alreadyLinked = groups[key, default: []].flatMap { $0.evidence.aliases }
            guard alreadyLinked.isEmpty, !receipt.evidence.keepSeparate else { continue }
            candidates[key] = records.values.compactMap { record in
                guard record.kind == "transaction", !record.deleted, record.key != key,
                      record.cardKey == receipt.evidence.cardKey, !claimed.contains(record.key),
                      let transaction = try? decoder.decode(TransactionSyncData.self, from: record.payload ?? Data()),
                      transaction.source == "shortcuts",
                      MailEvidence.matches(receipt.evidence.mail, transaction: transaction,
                                           aliases: receipt.evidence.merchantAliases) else { return nil }
                return record.key
            }.sorted()
            if candidates[key, default: []].isEmpty {
                suspected[key] = records.values.compactMap { record in
                    guard record.kind == "transaction", !record.deleted, record.key != key, record.cardKey == receipt.evidence.cardKey,
                          !claimed.contains(record.key),
                          let transaction = try? decoder.decode(TransactionSyncData.self, from: record.payload ?? Data()),
                          (["shortcuts", "manual", "csv", "sms"].contains(transaction.source) ||
                           (receipt.evidence.mail.source == "sms" && transaction.source == "email")),
                          MailEvidence.withinTimeWindow(receipt.evidence.mail, transaction: transaction) else { return nil }
                    let mail = receipt.evidence.mail
                    return (mail.amountCents == transaction.amountCents && mail.currency == transaction.currency)
                        || Set(([mail.merchant] + receipt.evidence.merchantAliases).map(MailEvidence.merchant)).contains(MailEvidence.merchant(transaction.merchant)) ? record.key : nil
                }.sorted()
            }
        }
        let demand = Dictionary(grouping: candidates.flatMap { key, values in values.map { ($0, key) } }, by: { $0.0 })
        for key in chosen.keys.sorted() {
            guard var receipt = chosen[key] else { continue }
            var evidence = receipt.evidence
            evidence.aliases = Array(Set(groups[key, default: []].flatMap { $0.evidence.aliases })).sorted()
            evidence.merchantAliases = Array(Set(groups[key, default: []].flatMap { $0.evidence.merchantAliases })).sorted()
            let possible = candidates[key, default: []]
            if possible.count == 1, let alias = possible.first, demand[alias]?.count == 1 {
                evidence.aliases.append(alias); evidence.aliases.sort(); claimed.insert(alias)
                let reviewKey = "document:" + MailReview.key(for: evidence.mail)
                if var reviewRecord = records[reviewKey],
                   var review = try? decoder.decode(DocumentSyncData.self, from: reviewRecord.payload ?? Data()), !review.isDeleted {
                    review.isDeleted = true
                    reviewRecord.payload = try? encoder.encode(review)
                    reviewRecord.revision = max(reviewRecord.revision, receipt.record.revision, records[alias]?.revision ?? .distantPast)
                    records[reviewKey] = reviewRecord
                }
            } else if !possible.isEmpty || !suspected[key, default: []].isEmpty {
                let review = MailReview(key: MailReview.key(for: evidence.mail), mail: evidence.mail,
                                        reason: "发现多笔相似交易，请选择对应交易或保留为另一笔。",
                                        candidateKeys: possible.isEmpty ? suspected[key, default: []] : possible, cardKey: evidence.cardKey)
                let reviewKey = "document:" + review.key
                // An explicit review decision remains authoritative after a stale peer arrives.
                if records[reviewKey] == nil {
                    let doc = DocumentSyncData(key: review.key, kind: "mailReview", content: (try? encoder.encode(review)) ?? Data(), isDeleted: false)
                    records[reviewKey] = SyncRecord(key: reviewKey, kind: "document", revision: receipt.record.revision,
                                                   deleted: false, payload: try? encoder.encode(doc))
                }
            }
            let aliases = evidence.aliases.filter { $0 != key }
            let aliasRecords = aliases.compactMap { records[$0] }.filter { !$0.deleted }
            let canonical = records[key]
            let revision = ([receipt.record.revision] + aliasRecords.map(\.revision) + [canonical?.revision].compactMap { $0 }).max() ?? receipt.record.revision
            if canonical?.deleted == true {
                // A user deletion is permanent for the message, including its old Wallet ID.
                for alias in aliases where records[alias]?.deleted != true {
                    records[alias] = SyncRecord(key: alias, kind: "transaction", revision: revision, deleted: true)
                }
            } else {
                var base = canonical.flatMap { try? decoder.decode(TransactionSyncData.self, from: $0.payload ?? Data()) }
                for alias in aliasRecords.sorted(by: { $0.key < $1.key }) {
                    guard let original = try? decoder.decode(TransactionSyncData.self, from: alias.payload ?? Data()) else { continue }
                    if var current = base {
                        // The email may have arrived first on another device with only defaults.
                        if current.category == "其他" { current.category = original.category }
                        if current.notes.isEmpty { current.notes = original.notes }
                        if current.paymentMethod == "待确认" { current.paymentMethod = original.paymentMethod }
                        if current.channel == "unknown" { current.channel = original.channel }
                        if (current.region ?? "").isEmpty { current.region = original.region; current.isOverseas = original.isOverseas }
                        current.isRewardEligible = current.isRewardEligible && original.isRewardEligible
                        if !evidence.mail.hasExactTime, HKCalendar.calendar.isDate(current.date, inSameDayAs: original.date) { current.date = original.date }
                        base = current
                    } else { base = original }
                    evidence.merchantAliases.append(original.merchant)
                }
                if var value = base {
                    project(evidence, onto: &value)
                    records[key] = SyncRecord(key: key, kind: "transaction", revision: revision, deleted: false,
                                              cardKey: evidence.cardKey, payload: try? encoder.encode(value))
                    for alias in aliases {
                        records[alias] = SyncRecord(key: alias, kind: "transaction", revision: revision, deleted: true)
                    }
                }
            }
            evidence.merchantAliases = Array(Set(evidence.merchantAliases)).sorted()
            // Keep every delivery receipt pointing to the same canonical transaction. Only
            // aliases are unioned; its original parsed notification remains auditable.
            for var member in groups[key, default: []] {
                member.evidence.aliases = evidence.aliases
                member.evidence.merchantAliases = Array(Set(member.evidence.merchantAliases + evidence.merchantAliases)).sorted()
                member.document.content = (try? encoder.encode(member.evidence)) ?? member.document.content
                member.record.payload = try? encoder.encode(member.document)
                records[member.record.key] = member.record
            }
            receipt.evidence = evidence
        }
        return records
    }

    static func project(_ evidence: MailEvidence, onto value: inout TransactionSyncData) {
        let mail = evidence.mail
        let currentRate = Decimal(string: value.exchangeRate) ?? 0
        // Bank notifications do not supply FX. Keep a valid personal rate for the
        // same currency; a rate attached to a different currency is never reusable.
        let keepRate = value.currency == mail.currency && !currentRate.isNaN && currentRate > 0 && currentRate <= 1000
        let exchangeRate = keepRate ? value.exchangeRate : evidence.exchangeRate
        value.merchant = mail.merchant; value.amountCents = mail.amountCents; value.currency = mail.currency
        value.exchangeRate = mail.currency == "HKD" ? "1" : exchangeRate
        if mail.hasExactTime || !HKCalendar.calendar.isDate(mail.date, inSameDayAs: value.date) { value.date = mail.date }
        value.source = mail.source; value.externalID = evidence.externalID
        if let payment = mail.paymentMethod, payment != PaymentMethod.unknown.rawValue { value.paymentMethod = payment }
        if let channel = mail.channel { value.channel = channel }
        if let region = mail.region, !region.isEmpty { value.region = region; value.isOverseas = region != "HK" }
    }
}
