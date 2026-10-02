import StoreKit
import SwiftUI

@MainActor
final class PurchaseStore: ObservableObject {
    static let shared = PurchaseStore()
    @Published private(set) var products: [Product] = []
    @Published private(set) var verifiedPro = false
    @Published private(set) var busy = false
    @Published var message: String?
    let salesEnabled: Bool
    private var updates: Task<Void, Never>?
    var access: ProductAccess { ProductAccess(salesEnabled: salesEnabled, verifiedPro: verifiedPro) }

    init(salesEnabled: Bool = SharedPreferences.salesEnabled) {
        self.salesEnabled = salesEnabled
        updates = Task { [weak self] in
            await self?.refresh()
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                if case .verified(let transaction) = result,
                   ProProduct(rawValue: transaction.productID) != nil {
                    await self?.refresh()
                    await transaction.finish()
                }
            }
        }
    }
    deinit { updates?.cancel() }

    func refresh() async {
        verifiedPro = await ProEntitlements.hasAccess()
        SharedPreferences.defaults.set(verifiedPro, forKey: "verifiedPro")
    }

    func loadProducts() async {
        guard salesEnabled, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let loaded = try await Product.products(for: ProProduct.allCases.map(\.rawValue))
            products = ProProduct.allCases.compactMap { id in loaded.first { $0.id == id.rawValue } }
            if products.isEmpty { message = L10n.tr("Planlar yüklenemedi. Biraz sonra yeniden dene.") }
        } catch { message = L10n.tr("App Store’a bağlanılamadı. Yeniden deneyebilirsin.") }
        await refresh()
    }

    func purchase(_ product: Product) async {
        guard salesEnabled, !busy, !verifiedPro,
              products.contains(where: { $0.id == product.id }) else { return }
        busy = true; message = nil; defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await refresh()
                await transaction.finish()
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
            message = L10n.tr(verifiedPro ? "Pro satın alımın geri yüklendi." : "Bu Apple hesabında etkin Pro satın alımı bulunamadı.")
        } catch { message = L10n.tr("Satın alımlar geri yüklenemedi. Yeniden deneyebilirsin.") }
    }
}
