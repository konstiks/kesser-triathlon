import EventKit
import Foundation

/// Liest Termine aus dem iPhone-Kalender, um freie Trainingszeit zu finden.
@MainActor
final class CalendarManager: ObservableObject {
    private let store = EKEventStore()
    @Published private(set) var hasAccess: Bool = false
    /// Wird erhöht, wenn sich Termine ändern, damit Ansichten neu rechnen.
    @Published private(set) var revision = 0

    init() {
        hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.revision += 1 }
        }
    }

    func requestAccess() async -> Bool {
        do {
            hasAccess = try await store.requestFullAccessToEvents()
        } catch {
            hasAccess = false
        }
        return hasAccess
    }

    func events(on day: Date) -> [EKEvent] {
        guard hasAccess else { return [] }
        let start = day.startOfDay
        let end = start.adding(days: 1)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    /// Termine, die wirklich Zeit blockieren (keine ganztägigen, nicht "frei").
    func busyEvents(on day: Date) -> [EKEvent] {
        events(on: day).filter { !$0.isAllDay && $0.availability != .free }
    }

    /// Freie Zeit im Trainingsfenster des Tages: Arbeitszeit, Termine und Zeitbudget berücksichtigt.
    /// Ganztägige Termine (Geburtstage, Feiertage, Urlaub …) blockieren keine Zeit.
    func availability(on day: Date, profile: AthleteProfile) -> DayAvailability {
        let events: [DateInterval]? = (hasAccess && profile.useCalendar)
            ? busyEvents(on: day).map { DateInterval(start: $0.startDate, end: max($0.endDate, $0.startDate)) }
            : nil
        return AvailabilityCalculator.compute(day: day, profile: profile, events: events)
    }
}
