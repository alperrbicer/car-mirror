import Foundation

/// Local counters only. A request is an attempt, not proof that Apple showed a prompt or got a rating.
public struct ReviewPromptPolicy: Codable, Equatable {
    public let firstUse: Date
    public private(set) var successfulDays: [Date] = []
    public private(set) var lastRequestedAt: Date?
    public private(set) var lastRequestedVersion: String?

    public init(firstUse: Date) { self.firstUse = firstUse }
    public mutating func completedPlayback(at date: Date, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        guard !successfulDays.contains(where: { calendar.isDate($0, inSameDayAs: day) }) else { return }
        successfulDays = Array((successfulDays + [day]).sorted().suffix(3))
    }
    public func isEligible(at date: Date, version: String) -> Bool {
        guard !version.isEmpty, successfulDays.count >= 3,
              date.timeIntervalSince(firstUse) >= 7 * 86_400,
              lastRequestedVersion != version else { return false }
        return lastRequestedAt.map { date.timeIntervalSince($0) >= 120 * 86_400 } ?? true
    }
    public mutating func requested(at date: Date, version: String) {
        lastRequestedAt = date; lastRequestedVersion = version
    }
}
