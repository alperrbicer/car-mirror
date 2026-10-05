import Foundation
import Security
import FirebaseAuth
import FirebaseFunctions
import FirebaseMessaging

@MainActor
protocol PushRegistering {
    func synchronize(token: String?, locale: String) async throws
}

/// Public product announcements work on Spark without an Auth/Functions/Firestore backend.
@MainActor
final class TopicPushRegistrationClient: PushRegistering {
    static let topic = "mirivo_announcements_ios"
    private let defaults: UserDefaults
    private let update: (Bool) async throws -> Void
    private let pendingKey = "notifications.topicMayBeSubscribed"

    init(defaults: UserDefaults = .standard, update: ((Bool) async throws -> Void)? = nil) {
        self.defaults = defaults
        self.update = update ?? { enabled in
            try await withCheckedThrowingContinuation { continuation in
                let request = TopicRequest(continuation)
                request.startTimeout()
                let completion: @Sendable (Error?) -> Void = { error in
                    Task { @MainActor in request.finish(error) }
                }
                if enabled {
                    Messaging.messaging().subscribe(toTopic: Self.topic, completion: completion)
                } else {
                    Messaging.messaging().unsubscribe(fromTopic: Self.topic, completion: completion)
                }
            }
        }
    }

    func synchronize(token: String?, locale: String) async throws {
        let enabled = token != nil
        // Persist before requesting: a timeout or restart must not lose an opt-out retry.
        if enabled { defaults.set(true, forKey: pendingKey) }
        else if !defaults.bool(forKey: pendingKey) { return }
        try await update(enabled)
        if !enabled { defaults.set(false, forKey: pendingKey) }
    }
}

@MainActor
private final class TopicRequest {
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
    func startTimeout() {
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            self?.finish(URLError(.timedOut))
        }
    }
    func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }
}

/// Monotonic revisions survive relaunch and prevent delayed requests undoing opt-out.
/// Stored per anonymous Firebase user; no credential or device token is stored here.
enum PushRevisionKeychain {
    static func next(userID: String, minimum: Int = 0) throws -> Int {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.alperbicer.carmirror.push-revision", kSecAttrAccount as String: userID]
        var read = query
        read[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw URLError(.cannotOpenFile) }
        let previous = (result as? Data).flatMap { String(data: $0, encoding: .utf8) }.flatMap(Int.init) ?? 0
        let next = max(previous, minimum) + 1
        let data = Data(String(next).utf8)
        if status == errSecSuccess {
            guard SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess
            else { throw URLError(.cannotWriteToFile) }
        } else {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw URLError(.cannotWriteToFile) }
        }
        return next
    }
}

@MainActor
final class PushRegistrationClient: PushRegistering {
    func synchronize(token: String?, locale: String) async throws {
        guard FirebaseServices.configured else { throw URLError(.unsupportedURL) }
        // Do not create an anonymous account for someone who has never opted in.
        if token == nil && Auth.auth().currentUser == nil { return }
        let user: User
        if let current = Auth.auth().currentUser { user = current }
        else { user = try await Auth.auth().signInAnonymously().user }
        var payload: [String: Any] = ["revision": try PushRevisionKeychain.next(userID: user.uid), "enabled": token != nil]
        if let token {
            payload["token"] = token
            payload["locale"] = locale
            payload["appVersion"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        }
        let callable = Functions.functions(region: FirebaseServices.region).httpsCallable("syncNotificationInstallation")
        callable.timeoutInterval = 15
        let response = try await callable.call(payload)
        if let data = response.data as? [String: Any], data["applied"] as? Bool == false {
            guard let revision = data["revision"] as? Int, revision > 0, revision < 9_007_199_254_740_990 else { throw URLError(.badServerResponse) }
            payload["revision"] = try PushRevisionKeychain.next(userID: user.uid, minimum: revision)
            let retry = try await callable.call(payload)
            guard (retry.data as? [String: Any])?["applied"] as? Bool == true else { throw URLError(.badServerResponse) }
        } else if (response.data as? [String: Any])?["applied"] as? Bool != true { throw URLError(.badServerResponse) }
    }
}
