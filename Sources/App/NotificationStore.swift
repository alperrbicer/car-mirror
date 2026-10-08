import UIKit
import UserNotifications
import FirebaseMessaging

@MainActor
protocol NotificationAuthorizationProviding {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
}

@MainActor
protocol NotificationPermissionProviding: NotificationAuthorizationProviding {
    func register()
    func unregister()
}

@MainActor
struct SystemNotificationPermission: NotificationPermissionProviding {
    func authorizationStatus() async -> UNAuthorizationStatus { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    func requestAuthorization() async throws -> Bool { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    func register() { UIApplication.shared.registerForRemoteNotifications() }
    func unregister() {
        UIApplication.shared.unregisterForRemoteNotifications()
        if FirebaseServices.configured { Messaging.messaging().isAutoInitEnabled = false }
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let identifiers = notifications.filter { $0.request.trigger is UNPushNotificationTrigger }.map { $0.request.identifier }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }
}

@MainActor
final class NotificationStore: ObservableObject {
    static let shared = NotificationStore(client: FirebaseServices.notificationClient())
    enum Status { case unavailable, off, permission, denied, registering, syncing, active, failed, removalPending }
    struct Navigation: Equatable { let id = UUID(); let route: NotificationRoute }
    @Published private(set) var enabled: Bool
    @Published private(set) var status: Status = .off
    @Published private(set) var pendingNavigation: Navigation?
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    var configured: Bool { client != nil }
    private let client: PushRegistering?
    private let permission: NotificationPermissionProviding
    private let defaults: UserDefaults
    private var token: String?
    private var synchronizedLocale: String?
    private var removalAcknowledged = false
    private var generation = 0
    private var worker: Task<Void, Never>?
    private var registrationTimeout: Task<Void, Never>?

    init(client: PushRegistering?, permission: NotificationPermissionProviding? = nil, defaults: UserDefaults = .standard) {
        self.client = client; self.permission = permission ?? SystemNotificationPermission(); self.defaults = defaults
        enabled = defaults.bool(forKey: "notifications.enabled")
        status = client == nil ? .unavailable : (enabled ? .registering : .off)
    }

    func setEnabled(_ value: Bool) async {
        guard configured else { return }
        enabled = value
        defaults.set(value, forKey: "notifications.enabled")
        generation += 1
        let expected = generation
        if !value {
            token = nil; registrationTimeout?.cancel(); registrationTimeout = nil; permission.unregister()
            pendingNavigation = nil
            scheduleSync()
            return
        }
        authorization = await permission.authorizationStatus()
        guard generation == expected, enabled else { return }
        if authorization == .notDetermined {
            status = .permission
            do { _ = try await permission.requestAuthorization() }
            catch { if generation == expected { status = .failed }; return }
            guard generation == expected, enabled else { return }
        }
        await refresh()
    }

    func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-mirivo-ui-testing") { return }
        #endif
        guard configured else { status = .unavailable; return }
        let expected = generation
        let current = await permission.authorizationStatus()
        guard expected == generation else { return }
        let authorizationChanged = authorization != current
        authorization = current
        if !authorizationChanged, removalAcknowledged,
           !enabled || !Self.allowsNotifications(current),
           [.off, .denied, .permission].contains(status) { return }
        // Opening settings or returning to the app must not restart a registration
        // that is already acknowledged or still in progress. Permission changes
        // and failed attempts continue through the normal reconciliation below.
        if enabled, Self.allowsNotifications(current), !authorizationChanged {
            if status == .active, token != nil, synchronizedLocale == L10n.language { return }
            if status == .registering, registrationTimeout != nil { return }
            if status == .syncing, worker != nil, token != nil { return }
        }
        generation += 1
        guard enabled, Self.allowsNotifications(current) else {
            token = nil; registrationTimeout?.cancel(); registrationTimeout = nil
            permission.unregister()
            scheduleSync()
            return
        }
        status = .registering
        permission.register()
        registrationTimeout?.cancel()
        registrationTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard let self, self.enabled, self.status == .registering else { return }
            self.status = .failed
        }
    }

    func receivedToken(_ value: String) {
        guard configured, enabled, Self.allowsNotifications(authorization), !value.isEmpty else { return }
        registrationTimeout?.cancel()
        registrationTimeout = nil
        if token == value {
            if worker != nil { return }
            if status == .active, synchronizedLocale == L10n.language { return }
        }
        token = value
        generation += 1
        scheduleSync()
    }
    func registrationFailed() {
        registrationTimeout?.cancel()
        registrationTimeout = nil
        if enabled, Self.allowsNotifications(authorization), status == .registering { status = .failed }
    }
    func navigate(userInfo: [AnyHashable: Any]) {
        guard enabled, let value = userInfo["route"] as? String, let route = NotificationRoute(rawValue: value) else { return }
        pendingNavigation = Navigation(route: route)
    }
    func consumedNavigation() { pendingNavigation = nil }
    static func allowsNotifications(_ value: UNAuthorizationStatus) -> Bool { [.authorized, .provisional, .ephemeral].contains(value) }

    private func scheduleSync() {
        guard worker == nil, let client else { return }
        worker = Task {
            while true {
                let expected = generation
                let target = enabled && Self.allowsNotifications(authorization) ? token : nil
                let locale = L10n.language
                // Never report ready until the server acknowledges this exact preference/token.
                status = .syncing
                do {
                    try await client.synchronize(token: target, locale: locale)
                    if generation == expected {
                        removalAcknowledged = target == nil
                        if !enabled { status = .off }
                        else if !Self.allowsNotifications(authorization) { status = authorization == .denied ? .denied : .permission }
                        else {
                            status = target == nil ? .registering : .active
                            if target != nil { synchronizedLocale = locale }
                        }
                    }
                } catch {
                    if generation == expected { status = target == nil ? .removalPending : .failed }
                }
                if generation == expected { break }
            }
            worker = nil
        }
    }
    func waitForSynchronization() async { await worker?.value }
}

final class MirivoAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let defaults = UserDefaults.standard
        if let identifier = defaults.string(forKey: "notifications.carConnectionReminder.request") {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        }
        for key in ["notifications.carConnectionReminder.request", "notifications.carConnectionReminder.enabled", "notifications.carConnectionReminder.handledSession"] {
            defaults.removeObject(forKey: key)
        }
        UNUserNotificationCenter.current().delegate = self
        if FirebaseServices.configured { Messaging.messaging().delegate = self }
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard FirebaseServices.configured else { return }
        Messaging.messaging().apnsToken = deviceToken
        Task { @MainActor in
            guard NotificationStore.shared.enabled else { return }
            Messaging.messaging().isAutoInitEnabled = true
            // Registration delivers the FID through the Messaging delegate.
            do { try await Messaging.messaging().register() }
            catch { NotificationStore.shared.registrationFailed() }
        }
    }
    func messaging(_ messaging: Messaging, didReceiveRegistration installationID: String?) {
        guard let installationID else { return }
        Task { @MainActor in NotificationStore.shared.receivedToken(installationID) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in NotificationStore.shared.registrationFailed() }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            completionHandler(NotificationStore.shared.enabled && notification.request.trigger is UNPushNotificationTrigger ? [.banner, .list, .sound] : [])
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                NotificationStore.shared.navigate(userInfo: response.notification.request.content.userInfo)
            }
            completionHandler()
        }
    }
}
