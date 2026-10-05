import StoreKit

enum ProEntitlements {
    static func hasAccess() async -> Bool {
        !(await activeProductIDs()).isEmpty
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
