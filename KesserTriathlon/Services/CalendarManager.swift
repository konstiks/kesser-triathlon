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

    /// Freie Zeit im Trainingsfenster des Tages.
    func availability(on day: Date, profile: AthleteProfile) -> DayAvailability {
        let budget = profile.maxMinutes(on: day)
        guard hasAccess, profile.useCalendar else {
            return DayAvailability(largestBlockMinutes: budget, totalFreeMinutes: budget,
                                   busyMinutes: 0, eventCount: 0, fromCalendar: false)
        }
        let cal = Calendar.de
        let start = day.startOfDay
        var windowStart = cal.date(bySettingHour: profile.dayStartHour, minute: 0, second: 0, of: start) ?? start
        let windowEnd = cal.date(bySettingHour: profile.dayEndHour, minute: 0, second: 0, of: start) ?? start.adding(days: 1)
        if day.isToday { windowStart = max(windowStart, Date.now) }
        guard windowEnd > windowStart else {
            return DayAvailability(largestBlockMinutes: 0, totalFreeMinutes: 0, busyMinutes: 0, eventCount: 0, fromCalendar: true)
        }

        let busy = busyEvents(on: day)
            .map { DateInterval(start: max($0.startDate, windowStart), end: max(min($0.endDate, windowEnd), max($0.startDate, windowStart))) }
            .filter { $0.duration > 0 }
            .sorted { $0.start < $1.start }

        // Überlappende Termine zusammenfassen
        var merged: [DateInterval] = []
        for interval in busy {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }

        var cursor = windowStart
        var largest: TimeInterval = 0
        var totalFree: TimeInterval = 0
        for interval in merged {
            let gap = interval.start.timeIntervalSince(cursor)
            if gap > 0 { largest = max(largest, gap); totalFree += gap }
            cursor = max(cursor, interval.end)
        }
        let tail = windowEnd.timeIntervalSince(cursor)
        if tail > 0 { largest = max(largest, tail); totalFree += tail }

        let busyMinutes = merged.reduce(0) { $0 + $1.duration } / 60
        // Nicht mehr als das persönliche Tagesbudget vorschlagen
        let block = min(Int(largest / 60), budget)
        return DayAvailability(largestBlockMinutes: block, totalFreeMinutes: Int(totalFree / 60),
                               busyMinutes: Int(busyMinutes), eventCount: busy.count, fromCalendar: true)
    }
}
