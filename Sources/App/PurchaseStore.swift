import StoreKit
import RevenueCat
import SwiftUI

@MainActor
final class PurchaseStore: ObservableObject {
    static let shared = PurchaseStore(observeRevenueCat: true, trialReminders: .shared)
    @Published private(set) var products: [Product] = []
    @Published private(set) var verifiedPro = false
    @Published private(set) var activeProductIDs = Set<String>()
    @Published private(set) var busy = false
    @Published private(set) var trialEligibleProductIDs = Set<String>()
    @Published var message: String?
    let salesEnabled: Bool
    private let observeRevenueCat: Bool
    private var updates: Task<Void, Never>?
    private var subscriptionUpdates: Task<Void, Never>?
    private let trialReminders: TrialReminderStore?
    private var refreshRevision = 0
    #if DEBUG
    @Published var developmentAccessEnabled = SharedPreferences.developmentAccessEnabled {
        didSet { SharedPreferences.defaults.set(developmentAccessEnabled, forKey: "developmentUnlimitedAccess") }
    }
    #endif
    var access: ProductAccess {
        #if DEBUG
        // Playback UI fixtures opt in explicitly; purchase tests use real StoreKit state.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-mirivo-ui-testing") && arguments.contains("-mirivo-ui-playback-access") {
            return ProductAccess(salesEnabled: salesEnabled, verifiedPro: true)
        }
        #endif
        return SharedPreferences.access(verifiedPro: verifiedPro, salesEnabled: salesEnabled)
    }
    var lifetimeOwned: Bool { activeProductIDs.contains(ProProduct.lifetime.rawValue) }
    var subscriptionActive: Bool { ProProduct.forSale.contains { activeProductIDs.contains($0.rawValue) } }

    func freeTrialDays(_ product: Product) -> Int? {
        guard trialEligibleProductIDs.contains(product.id), !verifiedPro,
              let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let days: Int
        switch offer.period.unit {
        case .day: days = offer.period.value * offer.periodCount
        case .week: days = offer.period.value * offer.periodCount * 7
        default: return nil
        }
        return days > 0 ? days : nil
    }

    func billingRate(_ product: Product) -> String {
        String(format: L10n.tr(product.id == ProProduct.weekly.rawValue ? "%@ / hafta" : "%@ / yıl"), product.displayPrice)
    }

    var annualSavingsPercent: Int? {
        guard let annual = products.first(where: { $0.id == ProProduct.yearly.rawValue }),
              let weekly = products.first(where: { $0.id == ProProduct.weekly.rawValue }), weekly.price > 0,
              annual.priceFormatStyle.currencyCode == weekly.priceFormatStyle.currencyCode else { return nil }
        let savings = NSDecimalNumber(decimal: (1 - annual.price / (weekly.price * 52)) * 100).doubleValue
        guard savings > 0, savings < 100 else { return nil }
        return Int(savings.rounded())
    }

    func canPurchase(_ product: Product) -> Bool {
        salesEnabled && !busy && !lifetimeOwned && products.contains(where: { $0.id == product.id })
            && !verifiedPro && ProProduct.forSale.contains(where: { $0.rawValue == product.id })
    }

    init(salesEnabled: Bool = SharedPreferences.salesEnabled, observeRevenueCat: Bool = false,
         trialReminders: TrialReminderStore? = nil) {
        self.salesEnabled = salesEnabled
        self.trialReminders = trialReminders
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
                    await transaction.finish()
                    await self?.refresh()
                    await self?.syncRevenueCat()
                }
            }
        }
        subscriptionUpdates = Task { [weak self] in
            for await _ in Product.SubscriptionInfo.Status.updates {
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }
    deinit { updates?.cancel(); subscriptionUpdates?.cancel() }

    func refresh() async {
        refreshRevision += 1
        let revision = refreshRevision
        let active = await ProEntitlements.activeProductIDs()
        var eligible = Set<String>()
        for product in products {
            if let subscription = product.subscription, await subscription.isEligibleForIntroOffer { eligible.insert(product.id) }
        }
        guard revision == refreshRevision else { return }
        activeProductIDs = active
        verifiedPro = !activeProductIDs.isEmpty
        trialEligibleProductIDs = eligible
        SharedPreferences.defaults.set(verifiedPro, forKey: "verifiedPro")
        await trialReminders?.refresh()
    }

    func loadProducts(reportErrors: Bool = true) async {
        guard salesEnabled, !busy else { return }
        busy = true; message = nil; defer { busy = false }
        do {
            let loaded = try await Product.products(for: ProProduct.forSale.map(\.rawValue))
            products = ProProduct.forSale.compactMap { id in loaded.first { $0.id == id.rawValue } }
            if products.isEmpty && reportErrors { message = L10n.tr("Planlar yüklenemedi. Biraz sonra yeniden dene.") }
        } catch {
            if reportErrors { message = L10n.tr("App Store’a bağlanılamadı. Yeniden deneyebilirsin.") }
        }
        await refresh()
    }

    func purchase(_ product: Product) async {
        guard canPurchase(product) else { return }
        busy = true; message = nil; defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                // The signed purchase can arrive before StoreKit's entitlement cache.
                // Keep the purchase pending briefly instead of reporting a false failure.
                for _ in 0..<20 {
                    await refresh()
                    if verifiedPro { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                await syncRevenueCat()
                if verifiedPro, transaction.offer?.type == .introductory,
                   transaction.offer?.paymentMode == .freeTrial {
                    await trialReminders?.refresh(requestPermission: true)
                }
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
