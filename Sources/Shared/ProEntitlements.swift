import StoreKit

/// Only the main app writes this cache after verifying a RevenueCat server response.
/// ReplayKit can read it without loading RevenueCat or relying on a user-facing switch.
struct ComplimentaryProCache {
    static var shared: Self { Self(defaults: SharedPreferences.defaults) }
    let defaults: UserDefaults
    private let identityKey = "pro.complimentary.customerID"
    private let recordKey = "pro.complimentary.verifiedRecord"

    private struct Record: Codable {
        let customerID: String
        let checkedAt: Date
        let grant: ComplimentaryProGrant?
    }

    func bind(to customerID: String) {
        if defaults.string(forKey: identityKey) != customerID {
            defaults.removeObject(forKey: recordKey)
            defaults.set(customerID, forKey: identityKey)
        }
    }

    func hasAccess(at now: Date = Date()) -> Bool {
        guard let id = defaults.string(forKey: identityKey), let record = record(),
              record.customerID == id else { return false }
        return record.grant?.isActive(for: id, at: now) == true
    }

    func update(customerID: String, checkedAt: Date, grant: ComplimentaryProGrant?, now: Date = Date()) {
        guard !customerID.isEmpty, defaults.string(forKey: identityKey) == customerID,
              checkedAt <= now.addingTimeInterval(300),
              record().map({ checkedAt >= $0.checkedAt }) ?? true,
              grant.map({ $0.customerID == customerID && $0.verifiedAt == checkedAt }) ?? true else { return }
        let record = Record(customerID: customerID, checkedAt: checkedAt, grant: grant)
        if let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: recordKey) }
    }

    func clear() {
        defaults.removeObject(forKey: recordKey)
        defaults.removeObject(forKey: identityKey)
    }

    private func record() -> Record? {
        guard let data = defaults.data(forKey: recordKey) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }
}

enum ProEntitlements {
    static func hasAccess(complimentaryCache: ComplimentaryProCache = .shared) async -> Bool {
        if !(await activeProductIDs()).isEmpty { return true }
        return complimentaryCache.hasAccess()
    }

    static func activeProductIDs() async -> Set<String> {
        let ids = Set(ProProduct.allCases.map(\.rawValue))
        var active = Set<String>()
        for await result in Transaction.currentEntitlements {
            // currentEntitlements includes subscriptions in Apple's billing grace period.
            guard case .verified(let transaction) = result, ids.contains(transaction.productID),
                  transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
            active.insert(transaction.productID)
        }
        return active
    }
}
