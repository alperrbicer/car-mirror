import Foundation
import DeviceCheck
import FirebaseCore
import FirebaseAppCheck
import FirebaseMessaging
import FirebaseRemoteConfig
import FirebaseAnalytics

final class MirivoAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        if DCAppAttestService.shared.isSupported { return AppAttestProvider(app: app) }
        return DeviceCheckProvider(app: app)
    }
}

enum FirebaseServices {
    static var configured: Bool { FirebaseApp.app() != nil }
    static var appStoreID: String { value("CMAppStoreID") }
    @MainActor static func notificationClient() -> PushRegistering? {
        guard configured else { return nil }
        if value("CMNotificationRegistrationMode") == "registry" { return PushRegistrationClient() }
        return TopicPushRegistrationClient()
    }
    static var region: String { value("CMFirebaseFunctionsRegion").isEmpty ? "europe-west1" : value("CMFirebaseFunctionsRegion") }
    static func value(_ key: String) -> String {
        let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.contains("$(") ? "" : value
    }

    static func configure() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-mirivo-ui-testing") { return }
        #endif
        guard !configured, let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path), options.bundleID == Bundle.main.bundleIdentifier else { return }
        #if DEBUG
        if value("CMFirebaseAppCheckDebugEnabled") == "YES" {
            AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        } else {
            AppCheck.setAppCheckProviderFactory(MirivoAppCheckProviderFactory())
        }
        #else
        AppCheck.setAppCheckProviderFactory(MirivoAppCheckProviderFactory())
        #endif
        FirebaseApp.configure(options: options)
        // No automatic push registration before explicit permission and preference checks.
        Messaging.messaging().isAutoInitEnabled = false
        applyAnalyticsPreference()
    }

    static func applyAnalyticsPreference(reset: Bool = false) {
        guard configured else { return }
        let enabled = UserDefaults.standard.bool(forKey: "analytics.enabled")
        Analytics.setAnalyticsCollectionEnabled(enabled)
        if reset && !enabled { Analytics.resetAnalyticsData() }
        Analytics.setConsent([.analyticsStorage: enabled ? .granted : .denied,
                              .adStorage: .denied, .adUserData: .denied, .adPersonalization: .denied])
    }

    enum Screen: String { case home, library, settings, notifications, requiredUpdate = "required_update" }
    static func recordScreen(_ screen: Screen) {
        guard configured, UserDefaults.standard.bool(forKey: "analytics.enabled") else { return }
        // Fixed screen names only: never source titles, search text, files, URLs or credentials.
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [AnalyticsParameterScreenName: screen.rawValue])
    }

    static func fetchUpdatePolicy(force: Bool) async throws -> Data? {
        guard configured else { return nil }
        let remote = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 300
        settings.fetchTimeout = 10
        remote.configSettings = settings
        let status = try await remote.fetch(withExpirationDuration: force ? 0 : 300)
        guard status == .success else { throw URLError(.badServerResponse) }
        _ = try await remote.activate()
        let value = remote.configValue(forKey: "ios_update_policy")
        guard value.source == .remote else { return nil }
        return value.dataValue
    }
}
