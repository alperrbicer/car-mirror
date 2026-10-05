import Foundation

@MainActor
final class AppUpdateStore: ObservableObject {
    static let shared = AppUpdateStore()
    @Published private(set) var requiredURL: URL?
    @Published private(set) var checking = false
    @Published private(set) var checkFailed = false
    private var lastCheck: Date?
    private let appStoreID: String
    private let version: String
    private let fetchPolicy: (Bool) async throws -> Data?

    init(appStoreID: String = FirebaseServices.appStoreID,
         version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
         fetchPolicy: @escaping (Bool) async throws -> Data? = FirebaseServices.fetchUpdatePolicy) {
        self.appStoreID = appStoreID; self.version = version; self.fetchPolicy = fetchPolicy
    }

    func refresh(force: Bool = false, now: Date = Date()) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-mirivo-ui-testing") {
            if ProcessInfo.processInfo.arguments.contains("-mirivo-required-update") {
                requiredURL = URL(string: "https://apps.apple.com/app/id123456789")
            }
            return
        }
        #endif
        guard !checking else { return }
        guard force || requiredURL != nil || lastCheck.map({ now.timeIntervalSince($0) >= 300 }) ?? true else { return }
        checking = true
        defer { checking = false; lastCheck = now }
        do {
            guard let data = try await fetchPolicy(force || requiredURL != nil || lastCheck == nil) else { requiredURL = nil; return }
            guard data.count <= 16_384 else { throw URLError(.badServerResponse) }
            let policy = try JSONDecoder().decode(AppUpdatePolicy.self, from: data)
            requiredURL = policy.requiredUpdateURL(currentVersion: version, appStoreID: appStoreID)
            checkFailed = false
        } catch {
            // Fail open, including after a previous required-update response.
            // No persisted lock survives a broken service, offline launch or rollback.
            requiredURL = nil
            checkFailed = true
        }
    }
}
