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
    @Published private(set) var complimentaryPro = false
    @Published private(set) var membershipCustomerID: String?
    @Published private(set) var refreshingMembership = false
    @Published var message: String?
    let salesEnabled: Bool
    private let observeRevenueCat: Bool
    private var updates: Task<Void, Never>?
    private var subscriptionUpdates: Task<Void, Never>?
    private var revenueCatUpdates: Task<Void, Never>?
    private var complimentaryRefresh: Task<Void, Never>?
    private let complimentaryClient: (any ComplimentaryProClient)?
    private let complimentaryCache: ComplimentaryProCache
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
        salesEnabled && !busy && !refreshingMembership && products.contains(where: { $0.id == product.id })
            && !verifiedPro && ProProduct.forSale.contains(where: { $0.rawValue == product.id })
    }

    init(salesEnabled: Bool = SharedPreferences.salesEnabled, observeRevenueCat: Bool = false,
         trialReminders: TrialReminderStore? = nil,
         complimentaryClient: (any ComplimentaryProClient)? = nil,
         complimentaryCache: ComplimentaryProCache = .shared, startsObserving: Bool = true) {
        self.salesEnabled = salesEnabled
        self.trialReminders = trialReminders
        self.complimentaryCache = complimentaryCache
        let key = (Bundle.main.object(forInfoDictionaryKey: "CMRevenueCatAPIKey") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Apple SDK keys only. Test Store keys must never ship in the App Store app.
        let usesRevenueCat = observeRevenueCat && salesEnabled && key.hasPrefix("appl_")
        self.observeRevenueCat = usesRevenueCat
        if usesRevenueCat && !Purchases.isConfigured {
            Purchases.logLevel = .warn
            Purchases.configure(with: Configuration.Builder(withAPIKey: key)
                .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
                .with(entitlementVerificationMode: .informational)
                .build())
        }
        self.complimentaryClient = complimentaryClient ?? (usesRevenueCat ? RevenueCatComplimentaryClient() : nil)
        if let client = self.complimentaryClient {
            membershipCustomerID = client.customerID
            complimentaryCache.bind(to: client.customerID)
            applyAccess()
        } else if observeRevenueCat {
            // A missing/invalid production SDK configuration must not reuse an old grant.
            complimentaryCache.clear()
        }
        guard startsObserving else { return }
        if usesRevenueCat && complimentaryClient == nil {
            revenueCatUpdates = Task { [weak self] in
                for await info in Purchases.shared.customerInfoStream {
                    guard !Task.isCancelled, let self else { break }
                    if let response = try? RevenueCatComplimentaryClient.response(from: info, customerID: Purchases.shared.appUserID) {
                        self.apply(response)
                    }
                }
            }
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
    deinit {
        updates?.cancel(); subscriptionUpdates?.cancel()
        revenueCatUpdates?.cancel(); complimentaryRefresh?.cancel()
    }

    func refresh(refreshComplimentary: Bool = true) async {
        refreshRevision += 1
        let revision = refreshRevision
        let active = await ProEntitlements.activeProductIDs()
        var eligible = Set<String>()
        for product in products {
            if let subscription = product.subscription, await subscription.isEligibleForIntroOffer { eligible.insert(product.id) }
        }
        guard revision == refreshRevision else { return }
        activeProductIDs = active
        applyAccess()
        trialEligibleProductIDs = eligible
        await trialReminders?.refresh()
        // Apple purchases and restores never wait for this additional network check.
        if refreshComplimentary { scheduleComplimentaryRefresh() }
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
        guard !busy, !refreshingMembership else { return }
        busy = true; message = nil; defer { busy = false }
        do {
            try await AppStore.sync()
            await refresh()
            await syncRevenueCat()
            message = L10n.tr(!activeProductIDs.isEmpty ? "Pro satın alımın geri yüklendi."
                : complimentaryPro ? "Ücretsiz Pro erişimin etkin." : "Bu Apple hesabında etkin Pro satın alımı bulunamadı.")
        } catch { message = L10n.tr("Satın alımlar geri yüklenemedi. Yeniden deneyebilirsin.") }
    }

    private func syncRevenueCat() async {
        guard observeRevenueCat, Purchases.isConfigured else { return }
        // Store purchases still use Apple's verified entitlements. Only promotional
        // grants are added from RevenueCat; stale paid entitlements cannot override Apple.
        if let info = try? await Purchases.shared.syncPurchases(),
           let response = try? RevenueCatComplimentaryClient.response(from: info, customerID: Purchases.shared.appUserID) {
            apply(response)
        }
    }

    func refreshMembership() async {
        guard let complimentaryClient, !busy, !refreshingMembership else { return }
        refreshingMembership = true
        defer { refreshingMembership = false }
        await complimentaryRefresh?.value
        do {
            apply(try await complimentaryClient.fetch(forceRefresh: true))
            await refresh(refreshComplimentary: false)
            message = L10n.tr(complimentaryPro ? "Ücretsiz Pro erişimin etkin." : "Üyelik durumu güncellendi.")
        } catch {
            applyAccess()
            message = L10n.tr("Üyelik durumu yenilenemedi. İnternet bağlantını kontrol edip yeniden dene.")
        }
    }

    private func scheduleComplimentaryRefresh() {
        guard let complimentaryClient, complimentaryRefresh == nil, !refreshingMembership else { return }
        complimentaryRefresh = Task { [weak self] in
            defer { self?.complimentaryRefresh = nil }
            do {
                let response = try await complimentaryClient.fetch(forceRefresh: false)
                guard !Task.isCancelled else { return }
                self?.apply(response)
            } catch { self?.applyAccess() }
        }
    }

    private func apply(_ response: ComplimentaryProResponse) {
        guard response.customerID == complimentaryClient?.customerID else { return }
        membershipCustomerID = response.customerID
        complimentaryCache.bind(to: response.customerID)
        complimentaryCache.update(customerID: response.customerID, checkedAt: response.requestDate, grant: response.grant)
        applyAccess()
    }

    private func applyAccess() {
        complimentaryPro = complimentaryClient != nil && complimentaryCache.hasAccess()
        verifiedPro = !activeProductIDs.isEmpty || complimentaryPro
        SharedPreferences.defaults.set(verifiedPro, forKey: "verifiedPro")
    }
}

struct ComplimentaryProResponse: Sendable {
    let customerID: String
    let requestDate: Date
    let grant: ComplimentaryProGrant?
}

@MainActor
protocol ComplimentaryProClient {
    var customerID: String { get }
    func fetch(forceRefresh: Bool) async throws -> ComplimentaryProResponse
}

@MainActor
struct RevenueCatComplimentaryClient: ComplimentaryProClient {
    var customerID: String { Purchases.shared.appUserID }

    func fetch(forceRefresh: Bool) async throws -> ComplimentaryProResponse {
        let id = customerID
        let info = try await Purchases.shared.customerInfo(fetchPolicy: forceRefresh ? .fetchCurrent : .notStaleCachedOrFetched)
        guard id == customerID else { throw VerificationError.changedCustomer }
        return try Self.response(from: info, customerID: id)
    }

    static func response(from info: CustomerInfo, customerID: String) throws -> ComplimentaryProResponse {
        // Informational mode exposes the signature result; enforce it for grants here.
        guard info.entitlements.verification == .verified else { throw VerificationError.unverified }
        let entitlement = info.entitlements[ComplimentaryProGrant.entitlementID]
        let grant: ComplimentaryProGrant?
        if let entitlement, entitlement.isActive, entitlement.store == .promotional,
           entitlement.verification == .verified, let expirationDate = entitlement.expirationDate {
            grant = ComplimentaryProGrant(customerID: customerID, verifiedAt: info.requestDate,
                                          expirationDate: expirationDate)
        } else { grant = nil }
        return ComplimentaryProResponse(customerID: customerID, requestDate: info.requestDate, grant: grant)
    }

    private enum VerificationError: Error { case unverified, changedCustomer }
}
