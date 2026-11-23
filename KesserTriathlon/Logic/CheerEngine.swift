import Foundation

/// Ein Anlass, zu dem die Pixel-Cheerleaderin auftaucht.
struct CheerEvent: Identifiable, Equatable {
    enum Kind { case milestone, personalBest, levelUp, tierUp, weekComplete, countdown }

    let id: String
    let kind: Kind
    let title: String
    let message: String
    let date: Date
    /// Höher = wichtiger (wenn mehrere gleichzeitig anstehen).
    let priority: Int

    var symbol: String {
        switch kind {
        case .milestone: return "flag.checkered"
        case .personalBest: return "stopwatch.fill"
        case .levelUp: return "arrow.up.circle.fill"
        case .tierUp: return "crown.fill"
        case .weekComplete: return "calendar.badge.checkmark"
        case .countdown: return "hourglass"
        }
    }
}

/// Findet Ereignisse zum Anfeuern: Trainings-Meilensteine, Bestleistungen, Level-Ups,
/// komplett erledigte Wochen und Countdown-Marken.
enum CheerEngine {
    static let milestones = [1, 5, 10, 25, 50, 75, 100, 150, 200, 250, 300, 400, 500]
    static let countdownMarks = [100, 50, 30, 14, 7, 1]

    static func allEvents(completed: [CompletedWorkout], planned: [PlannedWorkout],
                          profile: AthleteProfile, level: LevelInfo) -> [CheerEvent] {
        var events: [CheerEvent] = []
        let sorted = completed.sorted { $0.date < $1.date }

        // Meilensteine (Anzahl Trainings)
        for m in milestones where sorted.count >= m {
            let w = sorted[m - 1]
            let text: String
            switch m {
            case 1: text = "Das erste Training ist im Kasten! Der Anfang ist gemacht. 📣"
            case 5: text = "5 Trainings! Das wird zur Gewohnheit. Weiter so!"
            case 10: text = "10 Trainings! Zweistellig, Konsti! 🎉"
            default: text = "\(m) Trainings absolviert! Unglaublich, wie du dranbleibst!"
            }
            events.append(CheerEvent(id: "milestone-\(m)", kind: .milestone, title: "\(m). Training!",
                                     message: text, date: w.date, priority: 3))
        }

        // Bestleistungen je Disziplin: längste Distanz und schnellstes Tempo
        for d in Discipline.allCases {
            let mine = sorted.filter { $0.discipline == d && $0.distanceKm > 0 }
            var maxKm = 0.0
            var bestSpeed = 0.0
            let minKmForPace: Double = d == .swim ? 0.4 : (d == .bike ? 10 : 3)
            for (i, w) in mine.enumerated() {
                if i >= 2 && w.distanceKm > maxKm * 1.02 {
                    events.append(CheerEvent(
                        id: "pb-dist-\(w.id)", kind: .personalBest,
                        title: "Neue Bestmarke!",
                        message: "Längste \(d.name)-Einheit bisher: \(d.formatDistance(w.distanceKm))! 💪",
                        date: w.date, priority: 4))
                }
                maxKm = max(maxKm, w.distanceKm)

                if w.distanceKm >= minKmForPace && w.durationMinutes > 0 {
                    let speed = w.distanceKm / w.durationMinutes
                    if bestSpeed > 0 && speed > bestSpeed * 1.01 {
                        events.append(CheerEvent(
                            id: "pb-pace-\(w.id)", kind: .personalBest,
                            title: "Neue Bestzeit!",
                            message: "So schnell warst du beim \(d.name) noch nie: \(w.paceText ?? "")! 🔥",
                            date: w.date, priority: 5))
                    }
                    bestSpeed = max(bestSpeed, speed)
                }
            }
        }

        // Level-Ups
        if level.level > 1 {
            for l in 2...level.level {
                let isTier = (l - 1) % 5 == 0
                let tier = Tier(rawValue: min(3, (l - 1) / 5)) ?? .frischling
                events.append(CheerEvent(
                    id: "level-\(l)", kind: isTier ? .tierUp : .levelUp,
                    title: isTier ? "Neue Stufe: \(tier.name)!" : "Level \(l)!",
                    message: isTier ? "\(tier.motto) Pixel-Konsti hat sich verwandelt!" : "Level-Up! Pixel-Konsti wird immer kesser.",
                    date: .now, priority: isTier ? 6 : 2))
            }
        }

        // Komplett erledigte Wochen (mind. 3 Einheiten)
        let byWeek = Dictionary(grouping: planned.filter { $0.date < Date.now.startOfDay.adding(days: 1) }) { $0.date.startOfWeek }
        for (weekStart, items) in byWeek {
            let allOfWeek = planned.filter { $0.date.startOfWeek == weekStart }
            guard allOfWeek.count >= 3, allOfWeek.allSatisfy({ $0.status == .done }), !items.isEmpty else { continue }
            events.append(CheerEvent(
                id: "week-\(Int(weekStart.timeIntervalSince1970))", kind: .weekComplete,
                title: "Woche komplett!",
                message: "Alle \(allOfWeek.count) Einheiten der KW \(weekStart.weekOfYear) erledigt. Vorbildlich! ⭐️",
                date: weekStart.adding(days: 6), priority: 4))
        }

        // Countdown
        let days = profile.daysUntilRace
        if countdownMarks.contains(days) {
            let text = days == 1
                ? "Morgen ist es so weit! Ich steh an der Strecke und schrei mir die Seele aus dem Leib! 📣"
                : "Nur noch \(days) Tage bis zum \(profile.raceName)! Du schaffst das!"
            events.append(CheerEvent(id: "countdown-\(days)-\(Int(profile.raceDay.timeIntervalSince1970))",
                                     kind: .countdown, title: "Noch \(days) \(days == 1 ? "Tag" : "Tage")!",
                                     message: text, date: .now, priority: 1))
        }
        return events
    }

    /// Ereignisse, die noch nicht gefeiert wurden – wichtigste zuerst.
    static func pending(completed: [CompletedWorkout], planned: [PlannedWorkout],
                        profile: AthleteProfile, level: LevelInfo) -> [CheerEvent] {
        let seen = Set(profile.seenCheerIDs)
        return allEvents(completed: completed, planned: planned, profile: profile, level: level)
            .filter { !seen.contains($0.id) }
            .sorted { ($0.priority, $0.date) > ($1.priority, $1.date) }
    }
}
