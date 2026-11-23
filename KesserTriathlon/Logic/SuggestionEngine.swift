import Foundation

/// Freie Zeit an einem Tag (aus Kalender oder Einstellungen).
struct DayAvailability {
    /// Größter zusammenhängender freier Block in Minuten.
    let largestBlockMinutes: Int
    let totalFreeMinutes: Int
    let busyMinutes: Int
    let eventCount: Int
    /// true, wenn die Werte aus dem Kalender stammen.
    let fromCalendar: Bool
}

struct Suggestion {
    enum Kind { case train, rest, race, done }

    let kind: Kind
    let discipline: Discipline?
    let intensity: Intensity
    let minutes: Int
    let headline: String
    let reasons: [String]
    /// Geplante Einheit, auf die sich der Vorschlag bezieht.
    let plannedID: UUID?
    /// Vorschlag für einen besseren Tag, falls heute keine Zeit ist.
    let moveTo: Date?

    /// Kurzer Spruch für die Sprechblase von Pixel-Konsti.
    var speech: String {
        switch kind {
        case .race: return "Heute zählt's! 🏁"
        case .done: return "Erledigt! Jetzt Beine hoch. 😎"
        case .rest: return "Heute Pause. Morgen wieder Gas!"
        case .train:
            guard let d = discipline else { return "Auf geht's!" }
            switch intensity {
            case .recovery, .easy: return "\(d.shortName), schön locker heute."
            case .moderate: return "\(d.shortName), zügig! 💪"
            case .hard: return "\(d.shortName)-Intervalle. Kess bleiben! 🔥"
            }
        }
    }
}

/// Schlägt das sinnvollste Training für heute vor.
///
/// Berücksichtigt: Plan des Tages, verpasste Schlüsseleinheiten, freie Zeit laut Kalender,
/// Ermüdung (Ampel-Bewertungen, Belastungsanstieg) und die schwächste Disziplin.
enum SuggestionEngine {

    static func suggest(
        today: Date = .now,
        planned: [PlannedWorkout],
        completed: [CompletedWorkout],
        profile: AthleteProfile,
        progress: [DisciplineProgress],
        availability: (Date) -> DayAvailability
    ) -> Suggestion {
        let day = today.startOfDay
        var reasons: [String] = []

        // Wettkampftag
        if day.isSameDay(as: profile.raceDay) {
            return Suggestion(kind: .race, discipline: nil, intensity: .hard, minutes: 0,
                              headline: "Wettkampftag! Viel Erfolg beim \(profile.raceName)!",
                              reasons: ["Frühstück 3 h vorher, Wechselzone in Ruhe einrichten, locker einschwimmen."],
                              plannedID: nil, moveTo: nil)
        }

        let openToday = planned.filter { $0.date.isSameDay(as: day) && $0.status == .planned }
            .sorted { ($0.isKey ? 0 : 1, $0.minutes) < ($1.isKey ? 0 : 1, $1.minutes) }
        let doneToday = completed.filter { $0.date.isSameDay(as: day) }

        if openToday.isEmpty && !doneToday.isEmpty {
            let mins = Int(doneToday.reduce(0) { $0 + $1.durationMinutes })
            return Suggestion(kind: .done, discipline: doneToday.first?.discipline, intensity: .recovery, minutes: mins,
                              headline: "Training erledigt. Stark!",
                              reasons: ["Heute schon \(formatMinutes(mins)) trainiert. Jetzt Regeneration: trinken, essen, schlafen."],
                              plannedID: nil, moveTo: nil)
        }

        // Ermüdung
        let fatigue = fatigueLevel(completed: completed, now: today)
        // Freie Zeit
        let avail = availability(day)

        // Kandidat bestimmen
        var discipline: Discipline?
        var intensity: Intensity = .easy
        var minutes = 0
        var plannedID: UUID?
        var headline = ""

        let weekStart = day.startOfWeek
        let missedKey = planned.filter {
            $0.status == .planned && $0.isKey && $0.date >= weekStart && $0.date < day
        }.sorted { $0.date > $1.date }.first

        if let p = openToday.first {
            discipline = p.discipline
            intensity = p.intensity
            minutes = p.minutes
            plannedID = p.id
            headline = p.title
            reasons.append("Laut Plan: \(p.title) (\(formatMinutes(p.minutes)), \(p.intensity.shortName)).")
        } else if let m = missedKey, avail.largestBlockMinutes >= 30, !profile.restDays.contains(day.weekdayIndex) {
            discipline = m.discipline
            intensity = m.intensity
            minutes = m.minutes
            plannedID = m.id
            headline = "Nachholen: \(m.title)"
            reasons.append("Die Schlüsseleinheit vom \(m.date.weekdayName) fehlt noch. Heute wäre Platz dafür.")
        } else if profile.restDays.contains(day.weekdayIndex) || fatigue >= 2 {
            return Suggestion(kind: .rest, discipline: nil, intensity: .recovery, minutes: 0,
                              headline: fatigue >= 2 ? "Erholung statt Training" : "Ruhetag",
                              reasons: fatigue >= 2
                                ? ["Deine letzten Bewertungen waren rot. Der Körper braucht Pause, um stärker zu werden."]
                                : ["Ruhetage gehören zum Plan. Etwas Mobility oder ein Spaziergang ist okay."],
                              plannedID: nil, moveTo: nil)
        } else {
            // Kein Plan für heute: schwächste Disziplin locker
            let weakest = progress.min(by: { $0.readiness < $1.readiness })?.discipline ?? .run
            discipline = weakest
            intensity = .easy
            minutes = min(45, max(30, avail.largestBlockMinutes - 15))
            headline = "Bonus: lockeres \(weakest.name)"
            reasons.append("Heute ist nichts geplant. \(weakest.name) ist gerade deine schwächste Disziplin.")
        }

        // Ermüdung → Intensität und Umfang reduzieren
        if fatigue >= 2 {
            intensity = .recovery
            minutes = Int(Double(minutes) * 0.6)
            reasons.append("Mehrere rote Ampeln in Folge: nur regenerativ und kürzer als geplant.")
        } else if fatigue == 1 && intensity > .easy {
            intensity = .easy
            minutes = Int(Double(minutes) * 0.75)
            reasons.append("Du warst zuletzt ziemlich platt (gelb/rot). Deshalb heute locker statt zügig oder hart.")
        } else if fatigue == 0 && recentlyFresh(completed: completed, now: today) && intensity == .easy && plannedID != nil {
            reasons.append("Du fühlst dich gerade frisch (grüne Ampeln). Wenn's läuft, darf die zweite Hälfte etwas zügiger sein.")
        }

        // Verfügbarkeit
        var moveTo: Date?
        let usable = avail.largestBlockMinutes - 10   // Puffer für Umziehen/Duschen
        if usable < 20 {
            let suggestionDay = nextDayWithTime(after: day, minutes: minutes, planned: planned, profile: profile, availability: availability)
            moveTo = suggestionDay
            var why = avail.fromCalendar
                ? "Dein Kalender ist heute ziemlich voll (\(avail.eventCount) Termine)."
                : "Heute ist laut deinen Einstellungen keine Trainingszeit."
            if let s = suggestionDay { why += " Besser auf \(s.weekdayName) verschieben." }
            reasons.append(why)
            return Suggestion(kind: .rest, discipline: discipline, intensity: intensity, minutes: minutes,
                              headline: "Heute keine Zeit? Dann verschieben.",
                              reasons: reasons, plannedID: plannedID, moveTo: moveTo)
        } else if usable < minutes {
            let shortened = max(20, usable)
            reasons.append(avail.fromCalendar
                ? "Laut Kalender hast du max. \(formatMinutes(avail.largestBlockMinutes)) am Stück frei. Also kürzer: \(formatMinutes(shortened))."
                : "Dein Zeitbudget heute: \(formatMinutes(avail.largestBlockMinutes)). Also kürzer: \(formatMinutes(shortened)).")
            if intensity == .easy && shortened < minutes / 2 {
                intensity = .moderate
                reasons.append("Weniger Zeit → dafür etwas zügiger (GA2).")
            }
            minutes = shortened
        } else if avail.fromCalendar {
            reasons.append("Im Kalender ist genug Luft: \(formatMinutes(avail.largestBlockMinutes)) am Stück frei.")
        }

        // Rückstand in einer Disziplin
        if let d = discipline, let p = progress.first(where: { $0.discipline == d }), p.readiness < 0.3 {
            reasons.append("\(d.name) hinkt noch hinterher (\(Int(p.readiness * 100)) % Formstand). Gut, dass es heute dran ist.")
        }

        let phase = PlanGenerator.phase(on: day, profile: profile)
        if phase == .taper {
            reasons.append("Tapering: lieber etwas weniger als zu viel.")
        }

        return Suggestion(kind: .train, discipline: discipline, intensity: intensity, minutes: max(15, minutes / 5 * 5),
                          headline: headline, reasons: reasons, plannedID: plannedID, moveTo: moveTo)
    }

    /// 0 = frisch, 1 = angeschlagen, 2 = müde
    static func fatigueLevel(completed: [CompletedWorkout], now: Date) -> Int {
        let recent = completed.filter { $0.date >= now.adding(days: -4) && $0.isRated }
            .sorted { $0.date > $1.date }
            .prefix(3)
        let reds = recent.filter { $0.mood == .red || $0.effort == .red }.count
        let yellows = recent.filter { $0.mood == .yellow || $0.effort == .yellow }.count

        // Belastungssprung: letzte 7 Tage vs. Durchschnitt der 3 Wochen davor
        let acute = ProgressEngine.minutes(lastDays: 7, completed: completed, now: now)
        let previous = completed.filter { $0.date >= now.adding(days: -28) && $0.date < now.adding(days: -7) }
            .reduce(0) { $0 + $1.durationMinutes } / 3
        let spike = previous > 60 && acute / previous > 1.5

        if reds >= 2 || (reds >= 1 && spike) { return 2 }
        if reds == 1 || yellows >= 2 || spike { return 1 }
        return 0
    }

    static func recentlyFresh(completed: [CompletedWorkout], now: Date) -> Bool {
        let recent = completed.filter { $0.date >= now.adding(days: -5) && $0.isRated }
            .sorted { $0.date > $1.date }
            .prefix(2)
        return recent.count == 2 && recent.allSatisfy { $0.mood == .green && $0.effort != .red }
    }

    /// Nächster Tag (max. 6 Tage voraus) mit genug Zeit und ohne andere Schlüsseleinheit.
    static func nextDayWithTime(after day: Date, minutes: Int, planned: [PlannedWorkout],
                                profile: AthleteProfile, availability: (Date) -> DayAvailability) -> Date? {
        for offset in 1...6 {
            let d = day.adding(days: offset)
            if d >= profile.raceDay { return nil }
            if profile.restDays.contains(d.weekdayIndex) { continue }
            let hasKey = planned.contains { $0.date.isSameDay(as: d) && $0.isKey && $0.status == .planned }
            if hasKey { continue }
            if availability(d).largestBlockMinutes - 10 >= minutes { return d }
        }
        return nil
    }
}
