import Foundation

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
/// Berücksichtigt: Plan des Tages, verpasste Einheiten, freie Zeit laut Kalender,
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
        // Verpasste Einheit dieser Woche (wichtige zuerst, dann die jüngste)
        let missed = planned.filter {
            $0.status == .planned && $0.date >= weekStart && $0.date < day
        }.sorted { ($0.isKey ? 0 : 1, -$0.date.timeIntervalSince1970) < ($1.isKey ? 0 : 1, -$1.date.timeIntervalSince1970) }.first

        if let p = openToday.first {
            discipline = p.discipline
            intensity = p.intensity
            minutes = p.minutes
            plannedID = p.id
            headline = p.title
            reasons.append("Laut Plan: \(p.title) (\(formatMinutes(p.minutes)), \(p.intensity.shortName)).")
        } else if let m = missed, avail.largestBlockMinutes >= 30, fatigue < 2 {
            discipline = m.discipline
            intensity = m.intensity
            minutes = m.minutes
            plannedID = m.id
            headline = "Nachholen: \(m.title)"
            reasons.append(m.isKey
                ? "Die wichtige Einheit vom \(m.weekdayText) fehlt noch. Heute wäre Platz dafür."
                : "Die Einheit vom \(m.weekdayText) ist offen geblieben. Heute wäre Zeit zum Nachholen.")
        } else {
            let reason: String
            if fatigue >= 2 {
                reason = "Deine letzten Bewertungen waren rot. Der Körper braucht Pause, um stärker zu werden."
            } else if profile.restDays.contains(day.weekdayIndex) {
                reason = "Fester Ruhetag. Etwas Mobility oder ein Spaziergang ist okay."
            } else {
                reason = "Heute ist kein Training geplant. Erholung gehört zum Plan, genieß den freien Tag!"
            }
            let next = planned.filter { $0.status == .planned && $0.date > day }.min { $0.date < $1.date }
            var restReasons = [reason]
            if let next { restReasons.append("Nächste Einheit: \(next.title) am \(next.weekdayText).") }
            return Suggestion(kind: .rest, discipline: nil, intensity: .recovery, minutes: 0,
                              headline: fatigue >= 2 ? "Erholung statt Training" : "Trainingsfreier Tag",
                              reasons: restReasons, plannedID: nil, moveTo: nil)
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
            var why: String
            switch avail.limit {
            case .dayOver:
                why = "Dein Trainingsfenster für heute (bis \(profile.dayEndHour) Uhr) ist vorbei."
            case .work:
                why = "Neben deiner Arbeitszeit (\(profile.workTimeText)) bleibt heute zu wenig Zeit."
            case .calendar:
                why = "Deine Termine lassen heute kaum Luft (\(avail.eventCount) \(avail.eventCount == 1 ? "Termin" : "Termine"))."
            case .restDay:
                why = "Heute ist ein fester Ruhetag."
            case .budget, .none:
                why = "Dein Zeitbudget für heute ist zu knapp."
            }
            if let s = suggestionDay { why += " Besser auf \(s.weekdayName) verschieben." }
            reasons.append(why)
            return Suggestion(kind: .rest, discipline: discipline, intensity: intensity, minutes: minutes,
                              headline: "Heute keine Zeit? Dann verschieben.",
                              reasons: reasons, plannedID: plannedID, moveTo: moveTo)
        } else if usable < minutes {
            let shortened = max(20, usable)
            let source: String
            switch avail.limit {
            case .calendar: source = "Laut Kalender"
            case .work: source = "Neben der Arbeit"
            default: source = "Heute"
            }
            reasons.append("\(source) hast du max. \(formatMinutes(avail.largestBlockMinutes)) am Stück frei. Also kürzer: \(formatMinutes(shortened)).")
            if intensity == .easy && shortened < minutes / 2 {
                intensity = .moderate
                reasons.append("Weniger Zeit → dafür etwas zügiger (GA2).")
            }
            minutes = shortened
        } else if avail.fromCalendar && avail.eventCount > 0 {
            reasons.append("Trotz Terminen genug Luft: \(formatMinutes(avail.largestBlockMinutes)) am Stück frei.")
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

    /// Nächster Tag (max. 6 Tage voraus) mit genug Zeit und ohne andere wichtige Einheit.
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
