import Foundation
import FirebaseAnalytics
import FirebaseCrashlytics

/// Only closed vocabularies cross the analytics boundary. Never accept arbitrary payloads.
struct MeasurementEvent: Equatable {
    enum Name: String { case sourceSave = "source_save", playbackStart = "playback_start", playbackError = "playback_error", connection = "display_connection", paywallView = "paywall_view", purchase = "purchase_result", restore = "restore_result" }
    enum Outcome: String { case started, success, failure, cancelled, pending, unverified, empty }
    enum Route: String { case phone, cast, airplay, external }
    enum Plan: String { case weekly, yearly, unknown }
    enum Operation: String { case add, update }
    let name: Name
    let outcome: Outcome
    var route: Route? = nil
    var sourceKind: MediaSourceKind? = nil
    var plan: Plan? = nil
    var operation: Operation? = nil

    var parameters: [String: String] {
        var result = ["outcome": outcome.rawValue]
        result["route"] = route?.rawValue
        result["source_kind"] = sourceKind?.rawValue
        result["plan"] = plan?.rawValue
        result["operation"] = operation?.rawValue
        return result
    }
}

@MainActor
protocol MeasurementBackend: AnyObject {
    var available: Bool { get }
    func log(_ event: MeasurementEvent)
    func disableAutomaticCrashUploads()
    func checkUnsentReports(_ completion: @escaping @MainActor @Sendable (Bool) -> Void)
    func sendUnsentReports()
    func deleteUnsentReports()
    func recordFailure(operation: MeasurementEvent.Name, failure: DiagnosticFailure)
}

@MainActor
final class AppMeasurement {
    static let shared = AppMeasurement(defaults: .standard, backend: FirebaseMeasurementBackend())
    static let crashConsentKey = "diagnostics.crashReports.enabled"
    private static let sessionConsentKey = "diagnostics.crashReports.sessionConsent"
    private let defaults: UserDefaults
    private let backend: any MeasurementBackend
    private var started = false
    private var consentRevision = 0
    private var revokedThisSession = false

    init(defaults: UserDefaults, backend: any MeasurementBackend) {
        self.defaults = defaults; self.backend = backend
    }

    func start() {
        guard !started, backend.available else { return }
        started = true
        let previousSessionConsented = defaults.bool(forKey: Self.sessionConsentKey)
        let enabledAtLaunch = defaults.bool(forKey: Self.crashConsentKey)
        defaults.set(enabledAtLaunch, forKey: Self.sessionConsentKey)
        // A persistent SDK opt-in would upload before we can check revocation on launch.
        // Keep automatic uploads off permanently; decide once for the previous session.
        backend.disableAutomaticCrashUploads()
        let revision = consentRevision
        backend.checkUnsentReports { [weak self] hasReports in
            guard let self, hasReports else { return }
            if previousSessionConsented, enabledAtLaunch,
               self.defaults.bool(forKey: Self.crashConsentKey), self.consentRevision == revision {
                self.backend.sendUnsentReports()
            } else { self.backend.deleteUnsentReports() }
        }
    }

    func setCrashReportsEnabled(_ enabled: Bool) {
        consentRevision += 1
        defaults.set(enabled, forKey: Self.crashConsentKey)
        if !enabled { revokedThisSession = true }
        // Re-enabling in the same process must not resurrect reports from before revocation.
        defaults.set(enabled && !revokedThisSession, forKey: Self.sessionConsentKey)
        guard backend.available else { return }
        backend.disableAutomaticCrashUploads()
        if !enabled { backend.deleteUnsentReports() }
    }

    func record(_ event: MeasurementEvent) {
        guard backend.available, defaults.bool(forKey: "analytics.enabled") else { return }
        backend.log(event)
    }

    func failure(_ operation: MeasurementEvent.Name, error: Error) {
        failure(operation, failure: DiagnosticFailure(error))
    }

    func failure(_ operation: MeasurementEvent.Name, failure: DiagnosticFailure) {
        guard backend.available, defaults.bool(forKey: Self.crashConsentKey),
              defaults.bool(forKey: Self.sessionConsentKey) else { return }
        backend.recordFailure(operation: operation, failure: failure)
    }
}

@MainActor
private final class FirebaseMeasurementBackend: MeasurementBackend {
    var available: Bool { FirebaseServices.configured }
    func log(_ event: MeasurementEvent) { Analytics.logEvent(event.name.rawValue, parameters: event.parameters) }
    func disableAutomaticCrashUploads() { Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false) }
    func checkUnsentReports(_ completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        Crashlytics.crashlytics().checkForUnsentReports { available in
            Task { @MainActor in completion(available) }
        }
    }
    func sendUnsentReports() { Crashlytics.crashlytics().sendUnsentReports() }
    func deleteUnsentReports() { Crashlytics.crashlytics().deleteUnsentReports() }
    func recordFailure(operation: MeasurementEvent.Name, failure: DiagnosticFailure) {
        // Original NSError userInfo, descriptions, domains and URLs never reach the SDK.
        let safe = NSError(domain: "Mirivo.\(operation.rawValue).\(failure.family.rawValue)", code: failure.code)
        Crashlytics.crashlytics().record(error: safe)
    }
}

/// Measures actual playing time, excluding loading and pauses, once per playback attempt.
@MainActor
final class PlaybackMeasurement {
    private let record: @MainActor (MeasurementEvent) -> Void
    private let completed: @MainActor () -> Void
    private let uptime: () -> TimeInterval
    private var route: MeasurementEvent.Route?
    private var didStart = false
    private var playingSince: TimeInterval?
    private var played: TimeInterval = 0

    init(record: @escaping @MainActor (MeasurementEvent) -> Void = { AppMeasurement.shared.record($0) },
         completed: @escaping @MainActor () -> Void = { AppReviewStore.shared.completedPlayback() },
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.record = record; self.completed = completed; self.uptime = uptime
    }

    func begin(route: MeasurementEvent.Route) {
        self.route = route; didStart = false; played = 0; playingSince = nil
        record(MeasurementEvent(name: .playbackStart, outcome: .started, route: route))
    }
    func playing(_ playing: Bool) {
        guard let route else { return }
        if playing {
            if !didStart {
                didStart = true
                record(MeasurementEvent(name: .playbackStart, outcome: .success, route: route))
            }
            if playingSince == nil { playingSince = uptime() }
        } else if let since = playingSince {
            played += max(0, uptime() - since); playingSince = nil
        }
    }
    func finish(failed: Bool = false) {
        guard let route else { return }
        playing(false)
        if failed {
            record(MeasurementEvent(name: didStart ? .playbackError : .playbackStart, outcome: .failure, route: route))
        } else if !didStart {
            record(MeasurementEvent(name: .playbackStart, outcome: .cancelled, route: route))
        } else if played >= 60 { completed() }
        self.route = nil
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Explicit, synthetic QA only; cannot run in a device/Release build or without debug mode.
@MainActor
enum MeasurementProbe {
    static func runIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-mirivo-measurement-probe"), arguments.contains("-FIRDebugEnabled"),
              !arguments.contains("-mirivo-ui-testing"), FirebaseServices.configured else { return }
        try? await Task.sleep(for: .seconds(5))
        let events: [MeasurementEvent] = [
            .init(name: .sourceSave, outcome: .success, sourceKind: .stream, operation: .add),
            .init(name: .playbackStart, outcome: .started, route: .phone),
            .init(name: .playbackStart, outcome: .success, route: .phone),
            .init(name: .playbackError, outcome: .failure, route: .phone),
            .init(name: .connection, outcome: .success, route: .cast),
            .init(name: .paywallView, outcome: .success),
            .init(name: .purchase, outcome: .cancelled, plan: .weekly),
            .init(name: .restore, outcome: .empty)
        ]
        events.forEach { AppMeasurement.shared.record($0) }
        AppMeasurement.shared.failure(.playbackError, error: NSError(domain: NSURLErrorDomain, code: -1001))
        if arguments.contains("-mirivo-crashlytics-test"),
           UserDefaults.standard.bool(forKey: AppMeasurement.crashConsentKey) {
            try? await Task.sleep(for: .seconds(5))
            fatalError("Mirivo Crashlytics simulator verification")
        }
    }
}
#endif
