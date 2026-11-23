import Foundation

/// Freie Zeit an einem Tag (aus Arbeitszeit, Kalender und persönlichem Budget).
struct DayAvailability {
    enum Limit {
        case none
        /// Fester Ruhetag
        case restDay
        /// Das Trainingsfenster des Tages ist (fast) vorbei
        case dayOver
        /// Arbeitszeit lässt kaum Platz
        case work
        /// Kalendertermine lassen kaum Platz
        case calendar
        /// Persönliches Zeitbudget ist klein
        case budget
    }

    /// Größter zusammenhängender freier Block in Minuten (max. Tagesbudget).
    let largestBlockMinutes: Int
    let totalFreeMinutes: Int
    let busyMinutes: Int
    /// Zahl der Kalendertermine, die Zeit blockieren (ohne ganztägige).
    let eventCount: Int
    /// true, wenn Kalendertermine berücksichtigt wurden.
    let fromCalendar: Bool
    let isWorkDay: Bool
    /// Was die Zeit begrenzt, wenn wenig frei ist.
    let limit: Limit

    static let none = DayAvailability(largestBlockMinutes: 0, totalFreeMinutes: 0, busyMinutes: 0,
                                      eventCount: 0, fromCalendar: false, isWorkDay: false, limit: .restDay)
}

enum AvailabilityCalculator {

    /// - Parameters:
    ///   - events: blockierende Termine (nil = Kalender nicht genutzt)
    ///   - now: für "heute" zählt nur die Zeit ab jetzt
    static func compute(day: Date, profile: AthleteProfile, events: [DateInterval]?, now: Date? = .now) -> DayAvailability {
        let budget = profile.maxMinutes(on: day)
        let work = profile.workInterval(on: day)
        guard budget > 0 else {
            return DayAvailability(largestBlockMinutes: 0, totalFreeMinutes: 0, busyMinutes: 0, eventCount: 0,
                                   fromCalendar: events != nil, isWorkDay: work != nil, limit: .restDay)
        }

        let start = day.startOfDay
        var windowStart = start.addingTimeInterval(TimeInterval(profile.dayStartHour * 3600))
        let windowEnd = start.addingTimeInterval(TimeInterval(profile.dayEndHour * 3600))
        if let now, day.isSameDay(as: now) { windowStart = max(windowStart, now) }
        guard windowEnd.timeIntervalSince(windowStart) >= 15 * 60 else {
            return DayAvailability(largestBlockMinutes: 0, totalFreeMinutes: 0, busyMinutes: 0, eventCount: 0,
                                   fromCalendar: events != nil, isWorkDay: work != nil, limit: .dayOver)
        }

        let eventIntervals = (events ?? []).compactMap { clip($0, windowStart, windowEnd) }
        var busy = eventIntervals
        if let work, let w = clip(work, windowStart, windowEnd) { busy.append(w) }
        busy.sort { $0.start < $1.start }

        // Überlappungen zusammenfassen
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

        let largestMinutes = Int(largest / 60)
        let block = min(largestMinutes, budget)

        // Was begrenzt?
        var limit = DayAvailability.Limit.none
        if block < 30 {
            let remainingWindow = Int(windowEnd.timeIntervalSince(windowStart) / 60)
            if remainingWindow < 45 && day.isSameDay(as: now ?? .distantPast) {
                limit = .dayOver
            } else {
                // Ohne Termine – wie viel wäre frei?
                let withoutEvents = compute(day: day, profile: profile, events: nil, now: now).largestBlockMinutes
                if !eventIntervals.isEmpty && withoutEvents >= 30 {
                    limit = .calendar
                } else if work != nil {
                    limit = .work
                } else {
                    limit = .budget
                }
            }
        } else if block < budget && !eventIntervals.isEmpty {
            limit = .calendar
        }

        return DayAvailability(
            largestBlockMinutes: block,
            totalFreeMinutes: Int(totalFree / 60),
            busyMinutes: Int(merged.reduce(0) { $0 + $1.duration } / 60),
            eventCount: eventIntervals.count,
            fromCalendar: events != nil,
            isWorkDay: work != nil,
            limit: limit
        )
    }

    /// Planbare Zeit eines Wochentags (ohne Kalender, ohne "jetzt").
    static func planningCapacity(day: Date, profile: AthleteProfile) -> Int {
        compute(day: day, profile: profile, events: nil, now: nil).largestBlockMinutes
    }

    private static func clip(_ i: DateInterval, _ s: Date, _ e: Date) -> DateInterval? {
        let start = max(i.start, s)
        let end = min(i.end, e)
        return end > start ? DateInterval(start: start, end: end) : nil
    }
}
