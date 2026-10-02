import StoreKit

enum ProEntitlements {
    static func hasAccess() async -> Bool {
        let ids = Set(ProProduct.allCases.map(\.rawValue))
        for await result in Transaction.currentEntitlements {
            // currentEntitlements includes subscriptions in Apple's billing grace period.
            guard case .verified(let transaction) = result, ids.contains(transaction.productID),
                  transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
            return true
        }
        return false
    }
}
