import XCTest
import StoreKit
import StoreKitTest
@testable import CarMirror

@MainActor
final class StoreKitIntegrationTests: XCTestCase {
    private func session() throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Mirivo", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }
    func testLifetimePurchaseRestoreAndRefund() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = PurchaseStore(salesEnabled: true)
        await store.loadProducts()
        XCTAssertEqual(store.products.map(\.id), ProProduct.forSale.map(\.rawValue))
        let product = try XCTUnwrap(store.products.first { $0.id == ProProduct.lifetime.rawValue })
        await store.purchase(product)
        await store.refresh()
        XCTAssertTrue(store.verifiedPro)
        XCTAssertTrue(store.lifetimeOwned)
        XCTAssertFalse(store.canPurchase(product))
        let restored = PurchaseStore(salesEnabled: true)
        await restored.restore()
        XCTAssertTrue(restored.verifiedPro)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        await store.refresh()
        XCTAssertFalse(store.verifiedPro)
    }
    func testSubscriptionExpiryRemovesAccess() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        _ = try await session.buyProduct(identifier: ProProduct.yearly.rawValue)
        let store = PurchaseStore(salesEnabled: true)
        await store.refresh()
        XCTAssertTrue(store.verifiedPro)
        try session.expireSubscription(productIdentifier: ProProduct.yearly.rawValue)
        await store.refresh()
        XCTAssertFalse(store.verifiedPro)
    }
    func testYearlyPurchaseRestoreAndLifetimeUpgrade() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = PurchaseStore(salesEnabled: true)
        await store.loadProducts()
        let yearly = try XCTUnwrap(store.products.first { $0.id == ProProduct.yearly.rawValue })
        let lifetime = try XCTUnwrap(store.products.first { $0.id == ProProduct.lifetime.rawValue })
        await store.purchase(yearly)
        XCTAssertTrue(store.subscriptionActive)
        XCTAssertFalse(store.canPurchase(yearly))
        XCTAssertTrue(store.canPurchase(lifetime))
        let restored = PurchaseStore(salesEnabled: true)
        await restored.restore()
        XCTAssertTrue(restored.subscriptionActive)
        await store.purchase(lifetime)
        XCTAssertTrue(store.lifetimeOwned)
        // Buying lifetime does not cancel Apple's existing annual subscription.
        try session.expireSubscription(productIdentifier: ProProduct.yearly.rawValue)
        await store.refresh()
        XCTAssertTrue(store.verifiedPro)
        XCTAssertTrue(store.lifetimeOwned)
        XCTAssertFalse(store.subscriptionActive)
    }
    func testDisabledSalesCannotStartPurchase() async throws {
        let session = try session()
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
