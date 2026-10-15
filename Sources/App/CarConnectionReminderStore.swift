import Combine
import UserNotifications

@MainActor
protocol CarConnectionReminderScheduling {
    func add(_ request: UNNotificationRequest) async throws
    func remove(identifier: String)
}

@MainActor
private struct SystemCarConnectionReminderScheduler: CarConnectionReminderScheduling {
    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }
    func remove(identifier: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

@MainActor
final class CarConnectionReminderStore: ObservableObject {
    static let shared = CarConnectionReminderStore()
    private static let enabledKey = "notifications.carConnectionReminder.enabled"
    private static let sessionKey = "notifications.carConnectionReminder.handledSession"
    private static let requestKey = "notifications.carConnectionReminder.request"
    private static let identifierPrefix = "mirivo.car-connection."

    @Published private(set) var enabled: Bool
    @Published private(set) var authorization: UNAuthorizationStatus?
    @Published private(set) var requestingPermission = false
    @Published private(set) var permissionFailed = false
    private let defaults: UserDefaults
    private let permission: NotificationAuthorizationProviding
    private let scheduler: CarConnectionReminderScheduling
    private var activeSession: String?
    private var preferenceRevision = 0
    private var worker: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, permission: NotificationAuthorizationProviding? = nil,
         scheduler: CarConnectionReminderScheduling? = nil) {
        self.defaults = defaults
        self.permission = permission ?? SystemNotificationPermission()
        self.scheduler = scheduler ?? SystemCarConnectionReminderScheduler()
        enabled = defaults.bool(forKey: Self.enabledKey)
    }

    func setEnabled(_ value: Bool) async {
        enabled = value
        defaults.set(value, forKey: Self.enabledKey)
        preferenceRevision += 1
        let revision = preferenceRevision
        permissionFailed = false
        requestingPermission = false
        guard value else { cancelReminder(); return }

        let current = await permission.authorizationStatus()
        guard revision == preferenceRevision else { return }
        authorization = current
        if current == .notDetermined {
            requestingPermission = true
            do { _ = try await permission.requestAuthorization() }
            catch {
                if revision == preferenceRevision { permissionFailed = true; requestingPermission = false }
                return
            }
            guard revision == preferenceRevision else { return }
            requestingPermission = false
        }
        await refreshAuthorization()
        // Enabling while connected applies to the next detected session.
    }

    func refreshAuthorization() async {
        let revision = preferenceRevision
        let current = await permission.authorizationStatus()
        guard revision == preferenceRevision else { return }
        authorization = current
        if NotificationStore.allowsNotifications(current) { permissionFailed = false }
    }

    func connected(sessionID: String) {
        guard activeSession != sessionID else { return }
        activeSession = sessionID
        // A scene can reconnect after a process restart. Keep its consumed marker
        // until an actual disconnect so it cannot produce another reminder.
        guard defaults.string(forKey: Self.sessionKey) != sessionID else { return }
        cancelReminder()
        defaults.set(sessionID, forKey: Self.sessionKey)
        guard enabled else { return }

        let request = Self.makeRequest()
        defaults.set(request.identifier, forKey: Self.requestKey)
        worker = Task { [weak self] in
            guard let self else { return }
            let current = await self.permission.authorizationStatus()
            guard self.isCurrent(request.identifier, sessionID: sessionID) else { return }
            self.authorization = current
            // Never ask for permission from a CarPlay callback or contact FCM.
            guard NotificationStore.allowsNotifications(current) else { return }
            do {
                try await self.scheduler.add(request)
            } catch {
                // An uncertain delivery must not be retried in the same session.
                self.scheduler.remove(identifier: request.identifier)
                return
            }
            if !self.isCurrent(request.identifier, sessionID: sessionID) {
                self.scheduler.remove(identifier: request.identifier)
            }
        }
    }

    func disconnected(sessionID: String) {
        guard activeSession == sessionID else { return }
        activeSession = nil
        defaults.removeObject(forKey: Self.sessionKey)
        cancelReminder()
    }

    private func isCurrent(_ identifier: String, sessionID: String) -> Bool {
        !Task.isCancelled && enabled && activeSession == sessionID
            && defaults.string(forKey: Self.requestKey) == identifier
    }

    private func cancelReminder() {
        worker?.cancel()
        if let identifier = defaults.string(forKey: Self.requestKey) {
            scheduler.remove(identifier: identifier)
            defaults.removeObject(forKey: Self.requestKey)
        }
    }

    static func makeRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = BrandIdentity.name
        content.body = L10n.tr("Mirivo araç bağlantısına hazır")
        content.sound = .default
        content.threadIdentifier = "mirivo.car-connection"
        // No category with allowInCarPlay: this reminder belongs on the phone.
        return UNNotificationRequest(identifier: identifierPrefix + UUID().uuidString, content: content, trigger: nil)
    }

    static func isReminder(_ request: UNNotificationRequest) -> Bool {
        request.identifier.hasPrefix(identifierPrefix) && !(request.trigger is UNPushNotificationTrigger)
    }

    func waitForScheduling() async { await worker?.value }
}
