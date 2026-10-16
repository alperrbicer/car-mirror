import Combine
import StoreKit
import UserNotifications

struct TrialReminder: Equatable {
    let transactionID: UInt64
    let expirationDate: Date
    let renewalRate: String
    var fireDate: Date { expirationDate.addingTimeInterval(-48 * 60 * 60) }
    var signature: String { "\(transactionID)|\(expirationDate.timeIntervalSince1970)|\(renewalRate)|\(L10n.language)" }
}

@MainActor
protocol TrialReminderProviding {
    func activeTrial() async throws -> TrialReminder?
}

@MainActor
struct StoreKitTrialReminderProvider: TrialReminderProviding {
    func activeTrial() async throws -> TrialReminder? {
        var trials: [StoreKit.Transaction] = []
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
            if ProProduct.forSale.contains(where: { $0.rawValue == transaction.productID }),
               transaction.offer?.type == .introductory, transaction.offer?.paymentMode == .freeTrial,
               let end = transaction.expirationDate, end > Date() { trials.append(transaction) }
        }
        guard !trials.isEmpty else { return nil }
        let products = try await Product.products(for: trials.map(\.productID))
        for transaction in trials {
            guard let product = products.first(where: { $0.id == transaction.productID }),
                  let subscription = product.subscription else { throw URLError(.cannotParseResponse) }
            // A cancellation changes renewal info before the entitlement expires.
            let statuses = try await subscription.status
            for status in statuses {
                guard status.state == .subscribed,
                      case .verified(let current) = status.transaction, current.id == transaction.id,
                      case .verified(let renewal) = status.renewalInfo, renewal.willAutoRenew,
                      renewal.autoRenewPreference == nil || renewal.autoRenewPreference == product.id,
                      let end = current.expirationDate else { continue }
                let price: String
                if let renewalPrice = renewal.renewalPrice, let currency = renewal.currency {
                    price = renewalPrice.formatted(.currency(code: currency.identifier).locale(product.priceFormatStyle.locale))
                } else { price = product.displayPrice }
                let rate = String(format: L10n.tr(product.id == ProProduct.weekly.rawValue ? "%@ / hafta" : "%@ / yıl"), price)
                return TrialReminder(transactionID: current.id, expirationDate: end, renewalRate: rate)
            }
        }
        return nil
    }
}

@MainActor
protocol TrialReminderScheduling {
    func add(_ request: UNNotificationRequest) async throws
    func pendingIdentifiers() async -> Set<String>
    func remove(identifier: String)
}

@MainActor
private struct SystemTrialReminderScheduler: TrialReminderScheduling {
    func add(_ request: UNNotificationRequest) async throws { try await UNUserNotificationCenter.current().add(request) }
    func pendingIdentifiers() async -> Set<String> {
        Set(await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier))
    }
    func remove(identifier: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

@MainActor
final class TrialReminderStore: ObservableObject {
    enum Status { case idle, off, permission, denied, scheduled, tooLate, failed }
    static let shared = TrialReminderStore()
    static let identifierPrefix = "mirivo.trial-ending."
    private static let enabledKey = "notifications.trialReminder.enabled"
    private static let requestKey = "notifications.trialReminder.request"
    private static let signatureKey = "notifications.trialReminder.signature"
    @Published private(set) var enabled: Bool
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var status: Status = .idle
    private let defaults: UserDefaults
    private let permission: NotificationAuthorizationProviding
    private let scheduler: TrialReminderScheduling
    private let provider: TrialReminderProviding
    private let now: () -> Date
    private var revision = 0

    init(defaults: UserDefaults = .standard, permission: NotificationAuthorizationProviding? = nil,
         scheduler: TrialReminderScheduling? = nil, provider: TrialReminderProviding? = nil,
         now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.permission = permission ?? SystemNotificationPermission()
        self.scheduler = scheduler ?? SystemTrialReminderScheduler()
        self.provider = provider ?? StoreKitTrialReminderProvider()
        self.now = now
        enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func setEnabled(_ value: Bool) async {
        enabled = value
        defaults.set(value, forKey: Self.enabledKey)
        await refresh(requestPermission: value)
    }

    func refreshAuthorization() async {
        authorization = await permission.authorizationStatus()
    }

    func refresh(requestPermission: Bool = false) async {
        revision += 1
        let expected = revision
        guard enabled else { cancelPending(); status = .off; return }
        let current = await permission.authorizationStatus()
        guard expected == revision else { return }
        authorization = current
        if !NotificationStore.allowsNotifications(authorization) { cancelPending() }
        do {
            let trial = try await provider.activeTrial()
            guard expected == revision else { return }
            guard let trial else { cancelPending(); status = .idle; return }
            guard trial.fireDate > now() else { cancelPending(); status = .tooLate; return }
            // Only a verified, active trial or an explicit settings action may ask.
            if authorization == .notDetermined, requestPermission {
                _ = try await permission.requestAuthorization()
                guard expected == revision else { return }
                let granted = await permission.authorizationStatus()
                guard expected == revision else { return }
                authorization = granted
            }
            guard NotificationStore.allowsNotifications(authorization) else {
                cancelPending()
                status = authorization == .denied ? .denied : .permission
                return
            }
            let pending = await scheduler.pendingIdentifiers()
            guard expected == revision else { return }
            if let identifier = defaults.string(forKey: Self.requestKey), pending.contains(identifier),
               defaults.string(forKey: Self.signatureKey) == trial.signature {
                status = .scheduled
                return
            }
            cancelPending()
            let interval = trial.fireDate.timeIntervalSince(now())
            guard interval > 0 else { status = .tooLate; return }
            let content = UNMutableNotificationContent()
            content.title = L10n.tr("Denemen 2 gün sonra bitiyor")
            content.body = String(format: L10n.tr("İptal etmezsen %@ ödemesi başlar. Aboneliğini App Store’dan yönetebilirsin."), trial.renewalRate)
            content.sound = .default
            content.threadIdentifier = "mirivo.trial-ending"
            let identifier = Self.identifierPrefix + UUID().uuidString
            let request = UNNotificationRequest(identifier: identifier, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
            // Persist first so a process restart can clean up an interrupted add.
            defaults.set(identifier, forKey: Self.requestKey)
            defaults.set(trial.signature, forKey: Self.signatureKey)
            do { try await scheduler.add(request) }
            catch {
                scheduler.remove(identifier: identifier)
                if expected == revision { cancelPending(); status = .failed }
                return
            }
            guard expected == revision else { scheduler.remove(identifier: identifier); return }
            status = .scheduled
        } catch {
            // A network failure is not evidence that an existing trial ended.
            if expected == revision { status = .failed }
        }
    }

    private func cancelPending() {
        if let identifier = defaults.string(forKey: Self.requestKey) { scheduler.remove(identifier: identifier) }
        defaults.removeObject(forKey: Self.requestKey)
        defaults.removeObject(forKey: Self.signatureKey)
    }

    static func isReminder(_ request: UNNotificationRequest) -> Bool {
        request.identifier.hasPrefix(identifierPrefix) && !(request.trigger is UNPushNotificationTrigger)
    }
}
