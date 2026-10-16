import XCTest
import StoreKit
import StoreKitTest
@testable import CarMirror

@MainActor
final class StoreKitIntegrationTests: XCTestCase {
    private func session() async throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Mirivo", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        let configured = try XCTUnwrap(session.disableDialogs ? session : nil,
                                       "StoreKit Test could not apply its local configuration. Stop before purchase; check the simulator runtime and Xcode test service.")
        // Test-service mutations return before StoreKit 2's transaction cache updates.
        for _ in 0..<50 {
            if await ProEntitlements.activeProductIDs().isEmpty { return configured }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("StoreKit did not clear the previous test's entitlements")
        throw NSError(domain: "Mirivo.StoreKitTest", code: 2)
    }
    #if DEBUG
    func testDevelopmentAccessDoesNotForgePurchasedEntitlements() {
        let previous = SharedPreferences.defaults.object(forKey: "developmentUnlimitedAccess")
        defer {
            if let previous { SharedPreferences.defaults.set(previous, forKey: "developmentUnlimitedAccess") }
            else { SharedPreferences.defaults.removeObject(forKey: "developmentUnlimitedAccess") }
        }
        let store = PurchaseStore(salesEnabled: true)
        store.developmentAccessEnabled = false
        XCTAssertFalse(store.access.fullAccess)
        store.developmentAccessEnabled = true
        XCTAssertTrue(store.access.fullAccess)
        XCTAssertTrue(SharedPreferences.access(verifiedPro: false, salesEnabled: true).fullAccess)
        XCTAssertFalse(store.verifiedPro)
        XCTAssertTrue(store.activeProductIDs.isEmpty)
        store.developmentAccessEnabled = false
        XCTAssertFalse(store.access.fullAccess)
        XCTAssertFalse(SharedPreferences.access(verifiedPro: false, salesEnabled: true).fullAccess)
    }
    #endif

    func testLifetimePurchaseRestoreAndRefund() async throws {
        let session = try await session()
        defer { session.clearTransactions() }
        let store = PurchaseStore(salesEnabled: true)
        await store.loadProducts()
        XCTAssertEqual(store.products.map(\.id), ProProduct.forSale.map(\.rawValue))
        let legacyProducts = try await Product.products(for: [ProProduct.lifetime.rawValue])
        let product = try XCTUnwrap(legacyProducts.first)
        _ = try await session.buyProduct(identifier: product.id)
        try await refresh(store, until: [product.id])
        XCTAssertTrue(store.verifiedPro)
        XCTAssertTrue(store.lifetimeOwned)
        XCTAssertFalse(store.canPurchase(product))
        let restored = PurchaseStore(salesEnabled: true)
        await restored.restore()
        XCTAssertTrue(restored.verifiedPro)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        try await refresh(store, until: [])
        XCTAssertFalse(store.verifiedPro)
    }
    func testSubscriptionExpiryRemovesAccess() async throws {
        let session = try await session()
        defer { session.clearTransactions() }
        _ = try await session.buyProduct(identifier: ProProduct.yearly.rawValue)
        let store = PurchaseStore(salesEnabled: true)
        try await refresh(store, until: [ProProduct.yearly.rawValue])
        XCTAssertTrue(store.verifiedPro)
        try session.expireSubscription(productIdentifier: ProProduct.yearly.rawValue)
        try await refresh(store, until: [])
        XCTAssertFalse(store.verifiedPro)
    }
    func testAnnualTrialEligibilityPurchaseAndRestore() async throws {
        let session = try await session()
        defer { session.clearTransactions() }
        let store = PurchaseStore(salesEnabled: true)
        await store.loadProducts()
        XCTAssertEqual(store.products.map(\.id), [ProProduct.yearly.rawValue])
        let annual = try XCTUnwrap(store.products.first)
        XCTAssertTrue(store.hasThreeDayTrial(annual))
        XCTAssertEqual(annual.price, Decimal(string: "19.99"))
        await store.purchase(annual)
        XCTAssertTrue(store.subscriptionActive, store.message ?? "The purchased subscription was not activated")
        let trial = try await verifiedAnnualTransaction()
        XCTAssertEqual(trial.offer?.type, .introductory)
        XCTAssertEqual(trial.offer?.paymentMode, .freeTrial)
        XCTAssertEqual(trial.price, 0)
        let trialEnd = try XCTUnwrap(trial.expirationDate)
        XCTAssertEqual(trialEnd.timeIntervalSince(trial.purchaseDate), 3 * 24 * 60 * 60, accuracy: 2)
        print("STOREKIT_EVIDENCE: trial environment=\(trial.environment.rawValue) price=\(trial.price ?? -1) durationSeconds=\(trialEnd.timeIntervalSince(trial.purchaseDate))")
        XCTAssertFalse(store.hasThreeDayTrial(annual))
        XCTAssertFalse(store.canPurchase(annual))
        let restored = PurchaseStore(salesEnabled: true)
        await restored.restore()
        XCTAssertTrue(restored.subscriptionActive)
        try session.forceRenewalOfSubscription(productIdentifier: annual.id)
        // The test service signs the renewal asynchronously.
        for _ in 0..<50 {
            if case .verified(let latest) = await StoreKit.Transaction.latest(for: annual.id), latest.id != trial.id { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        await store.refresh()
        let renewal = try await verifiedAnnualTransaction()
        XCTAssertNotEqual(renewal.id, trial.id)
        XCTAssertNil(renewal.offer)
        XCTAssertEqual(renewal.price, annual.price)
        let renewalEnd = try XCTUnwrap(renewal.expirationDate)
        XCTAssertEqual(renewalEnd.timeIntervalSince(renewal.purchaseDate), 365 * 24 * 60 * 60, accuracy: 24 * 60 * 60)
        XCTAssertTrue(store.subscriptionActive)
        print("STOREKIT_EVIDENCE: annual renewal environment=\(renewal.environment.rawValue) price=\(renewal.price ?? -1) durationSeconds=\(renewalEnd.timeIntervalSince(renewal.purchaseDate))")
    }

    func testCancelDuringTrialKeepsAccessUntilExpiry() async throws {
        let session = try await session()
        defer { session.clearTransactions() }
        let transaction = try await session.buyProduct(identifier: ProProduct.yearly.rawValue)
        XCTAssertEqual(transaction.environment, .xcode)
        XCTAssertEqual(transaction.offer?.paymentMode, .freeTrial)
        let local = try XCTUnwrap(session.allTransactions().first)
        try session.disableAutoRenewForTransaction(identifier: local.identifier)
        let store = PurchaseStore(salesEnabled: true)
        try await refresh(store, until: [ProProduct.yearly.rawValue])
        XCTAssertTrue(store.subscriptionActive, "Canceling renewal preserves the remaining trial")
        try session.expireSubscription(productIdentifier: ProProduct.yearly.rawValue)
        try await refresh(store, until: [])
        XCTAssertFalse(store.access.fullAccess)
    }

    private func verifiedAnnualTransaction() async throws -> StoreKit.Transaction {
        let latest = await StoreKit.Transaction.latest(for: ProProduct.yearly.rawValue)
        guard case .verified(let transaction) = latest else {
            XCTFail("Expected a cryptographically verified local annual transaction")
            throw NSError(domain: "Mirivo.StoreKitTest", code: 1)
        }
        XCTAssertEqual(transaction.environment, .xcode, "These tests must use local Xcode transactions only")
        return transaction
    }

    private func refresh(_ store: PurchaseStore, until expected: Set<String>) async throws {
        for _ in 0..<50 {
            await store.refresh()
            if store.activeProductIDs == expected { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("StoreKit entitlements did not settle: expected \(expected), received \(store.activeProductIDs)")
        throw NSError(domain: "Mirivo.StoreKitTest", code: 3)
    }

    func testDisabledSalesCannotStartPurchase() async throws {
        let session = try await session()
        defer { session.clearTransactions() }
        let products = try await Product.products(for: [ProProduct.lifetime.rawValue])
        let product = try XCTUnwrap(products.first)
        let store = PurchaseStore(salesEnabled: false)
        await store.loadProducts()
        await store.purchase(product)
        XCTAssertTrue(store.products.isEmpty)
        XCTAssertTrue(session.allTransactions().isEmpty)
        XCTAssertTrue(store.access.fullAccess)
    }
    func testKeychainRoundTripAndDeletion() throws {
        let id = UUID()
        defer { try? SourceKeychain.delete(id) }
        let secret = SourceSecret(url: URL(string: "https://server.example/list.m3u?token=private")!, username: "member", password: "not-a-real-password")
        try SourceKeychain.save(secret, id: id)
        let restored = try SourceKeychain.read(id)
        XCTAssertEqual(restored.url, secret.url)
        XCTAssertEqual(restored.password, secret.password)
        try SourceKeychain.delete(id)
        XCTAssertThrowsError(try SourceKeychain.read(id))
    }
}
