import SwiftUI
import StoreKit

@MainActor
final class AppReviewStore: ObservableObject {
    static let shared = AppReviewStore()
    @Published private(set) var policy: ReviewPromptPolicy
    private let defaults: UserDefaults
    private let now: () -> Date
    private let key = "reviewPrompt.policy"
    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults; self.now = now
        policy = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ReviewPromptPolicy.self, from: $0) }
            ?? ReviewPromptPolicy(firstUse: now())
        persist()
    }
    func completedPlayback() { policy.completedPlayback(at: now()); persist() }
    func eligible(version: String) -> Bool { policy.isEligible(at: now(), version: version) }
    func requested(version: String) { policy.requested(at: now(), version: version); persist() }
    private func persist() { defaults.set(try? JSONEncoder().encode(policy), forKey: key) }

    static func reviewURL(appStoreID: String) -> URL? {
        guard !appStoreID.isEmpty, appStoreID.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }
}

struct ReviewPromptContext {
    var rootAvailable = true
    var foreground = true
    var carPlay = false
    var broadcasting = false
    var modal = false
    var playback = false
    var pictureInPicture = false
    var purchase = false
    var allowsPrompt: Bool {
        rootAvailable && foreground && !carPlay && !broadcasting && !modal && !playback && !pictureInPicture && !purchase
    }
}

struct ReviewPromptPresenter: ViewModifier {
    @ObservedObject var model: MirrorModel
    @ObservedObject var playback: PlaybackController
    @ObservedObject private var reviews = AppReviewStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    let rootAvailable: Bool
    @State private var completedPlaybackThisVisit = false
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    private var safe: Bool {
        ReviewPromptContext(rootAvailable: rootAvailable, foreground: scenePhase == .active,
            carPlay: model.carPlayConnected, broadcasting: model.broadcasting,
            modal: model.presentingPlayer || model.presentingMembership,
            playback: playback.hasActivePlayback, pictureInPicture: playback.pictureInPictureActiveOrStarting,
            purchase: PurchaseStore.shared.busy).allowsPrompt
    }
    private var shouldRequest: Bool { safe && completedPlaybackThisVisit && reviews.eligible(version: version) }

    func body(content: Content) -> some View {
        content
            .onReceive(reviews.$policy.dropFirst()) { _ in completedPlaybackThisVisit = true }
            .onChange(of: scenePhase) { _, _ in completedPlaybackThisVisit = false }
            .task(id: shouldRequest) {
                guard shouldRequest else { return }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard !Task.isCancelled, shouldRequest,
                      let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                        .first(where: { $0.session.role == .windowApplication && $0.activationState == .foregroundActive }),
                      let window = scene.windows.first(where: \.isKeyWindow),
                      window.rootViewController?.presentedViewController == nil else { return }
                #if DEBUG
                guard !ProcessInfo.processInfo.arguments.contains("-mirivo-ui-testing") else { return }
                #endif
                completedPlaybackThisVisit = false
                reviews.requested(version: version)
                requestReview()
            }
    }
}
