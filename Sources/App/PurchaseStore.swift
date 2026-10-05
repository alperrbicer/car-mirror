import StoreKit
import RevenueCat
import SwiftUI

@MainActor
final class PurchaseStore: ObservableObject {
    static let shared = PurchaseStore(observeRevenueCat: true)
    @Published private(set) var products: [Product] = []
    @Published private(set) var verifiedPro = false
    @Published private(set) var activeProductIDs = Set<String>()
    @Published private(set) var busy = false
    @Published var message: String?
    let salesEnabled: Bool
    private let observeRevenueCat: Bool
    private var updates: Task<Void, Never>?
    var access: ProductAccess { ProductAccess(salesEnabled: salesEnabled, verifiedPro: verifiedPro) }
    var lifetimeOwned: Bool { activeProductIDs.contains(ProProduct.lifetime.rawValue) }
    var subscriptionActive: Bool { activeProductIDs.contains(ProProduct.yearly.rawValue) }

    func canPurchase(_ product: Product) -> Bool {
        salesEnabled && !busy && !lifetimeOwned && products.contains(where: { $0.id == product.id })
            && (!verifiedPro || product.id == ProProduct.lifetime.rawValue)
    }

    init(salesEnabled: Bool = SharedPreferences.salesEnabled, observeRevenueCat: Bool = false) {
        self.salesEnabled = salesEnabled
        let key = (Bundle.main.object(forInfoDictionaryKey: "CMRevenueCatAPIKey") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Apple SDK keys only. Test Store keys must never ship in the App Store app.
        self.observeRevenueCat = observeRevenueCat && salesEnabled && key.hasPrefix("appl_")
        if self.observeRevenueCat && !Purchases.isConfigured {
            Purchases.logLevel = .warn
            Purchases.configure(with: Configuration.Builder(withAPIKey: key)
                .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
                .build())
        }
        updates = Task { [weak self] in
            await self?.refresh()
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                if case .verified(let transaction) = result,
                   ProProduct(rawValue: transaction.productID) != nil {
                    await self?.refresh()
                    await transaction.finish()
                    await self?.syncRevenueCat()
                }
            }
        }
    }
    deinit { updates?.cancel() }

    func refresh() async {
        activeProductIDs = await ProEntitlements.activeProductIDs()
        verifiedPro = !activeProductIDs.isEmpty
        SharedPreferences.defaults.set(verifiedPro, forKey: "verifiedPro")
    }

    func loadProducts() async {
        guard salesEnabled, !busy else { return }
        busy = true; message = nil; defer { busy = false }
        do {
            let loaded = try await Product.products(for: ProProduct.forSale.map(\.rawValue))
            products = ProProduct.forSale.compactMap { id in loaded.first { $0.id == id.rawValue } }
            if products.isEmpty { message = L10n.tr("Planlar yüklenemedi. Biraz sonra yeniden dene.") }
        } catch { message = L10n.tr("App Store’a bağlanılamadı. Yeniden deneyebilirsin.") }
        await refresh()
    }

    func purchase(_ product: Product) async {
        guard canPurchase(product) else { return }
        busy = true; message = nil; defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await refresh()
                await transaction.finish()
                await syncRevenueCat()
                if !verifiedPro { message = L10n.tr("Satın alma henüz doğrulanamadı. Satın alımları geri yükleyebilirsin.") }
            case .success(.unverified): message = L10n.tr("Satın alma doğrulanamadı. Lütfen App Store hesabını kontrol et.")
            case .pending: message = L10n.tr("Satın alma onay bekliyor. Onaylandığında Pro otomatik açılacak.")
            case .userCancelled: break
            @unknown default: message = L10n.tr("Satın alma tamamlanamadı.")
            }
        } catch { message = L10n.tr("Satın alma tamamlanamadı. Yeniden deneyebilirsin.") }
    }

    func restore() async {
        guard !busy else { return }
        busy = true; message = nil; defer { busy = false }
        do {
            try await AppStore.sync()
            await refresh()
            await syncRevenueCat()
            message = L10n.tr(verifiedPro ? "Pro satın alımın geri yüklendi." : "Bu Apple hesabında etkin Pro satın alımı bulunamadı.")
        } catch { message = L10n.tr("Satın alımlar geri yüklenemedi. Yeniden deneyebilirsin.") }
    }

    private func syncRevenueCat() async {
        guard observeRevenueCat, Purchases.isConfigured else { return }
        // RevenueCat observes transactions; StoreKit remains the authority for phone
        // and ReplayKit access, including refunds and expiry while offline.
        _ = try? await Purchases.shared.syncPurchases()
    }

}
