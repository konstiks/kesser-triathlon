import Foundation
import SwiftData

/// Erzeugt einen periodisierten Trainingsplan von heute bis zum Wettkampf.
///
/// Angelehnt an etablierte Ansätze (klassische Periodisierung, 80/20-Prinzip, ~10-%-Regel):
/// - Phasen werden vom Wettkampf aus rückwärts gerechnet: Wettkampfwoche, Tapering,
///   2 Wochen Spitze, 6 Wochen Aufbau, 6 Wochen Grundlage. Alles davor ist eine sanfte Einstiegsphase.
/// - Der Wochenumfang startet beim bisherigen Umfang (bzw. einem Minimum je Niveau) und steigt
///   langsam bis zum Zielumfang des Niveaus, höchstens ~10 % pro Woche. Jede 4. Woche ist Entlastung.
/// - Die Zahl der Einheiten ergibt sich aus dem Umfang (anfangs wenige), höchstens die eingestellten Trainingstage.
/// - Disziplinen, in denen bisher wenig trainiert wurde, bekommen mehr Einheiten.
/// - Überwiegend locker; harte Einheiten erst ab der Aufbauphase (Einsteiger: moderat).
enum PlanGenerator {

    enum SessionKind {
        case swimTechnique, swimEndurance, runIntervals, runLong, runEasy, bikeTempo, bikeLong, brickRun

        var discipline: Discipline {
            switch self {
            case .swimTechnique, .swimEndurance: return .swim
            case .runIntervals, .runLong, .runEasy, .brickRun: return .run
            case .bikeTempo, .bikeLong: return .bike
            }
        }

        /// Gewicht beim Verteilen des Wochenumfangs.
        var weight: Double {
            switch self {
            case .bikeLong: return 1.6
            case .runLong: return 1.3
            case .brickRun: return 0.35
            default: return 1.0
            }
        }

        /// Bevorzugter Wochentag (0 = Montag).
        var preferredDay: Int {
            switch self {
            case .swimTechnique: return 1   // Di
            case .runIntervals: return 3    // Do
            case .swimEndurance: return 4   // Fr
            case .bikeLong, .brickRun: return 5   // Sa
            case .runLong: return 6         // So
            case .bikeTempo: return 2       // Mi
            case .runEasy: return 0         // Mo
            }
        }

        var isLong: Bool { self == .bikeLong || self == .runLong }

        var isKey: Bool {
            switch self {
            case .runLong, .bikeLong, .runIntervals: return true
            default: return false
            }
        }
    }

    /// Reihenfolge der Einheiten je Disziplin (1. Einheit der Woche, 2., 3. …).
    static func kinds(for d: Discipline) -> [SessionKind] {
        switch d {
        case .swim: return [.swimTechnique, .swimEndurance, .swimTechnique]
        case .bike: return [.bikeLong, .bikeTempo, .bikeTempo]
        case .run: return [.runLong, .runIntervals, .runEasy]
        }
    }

    struct WeekInfo {
        let start: Date
        let phase: TrainingPhase
        let isRecovery: Bool
        /// Wochen bis zur Wettkampfwoche (0 = Wettkampfwoche).
        let weeksToRace: Int
        let taperStep: Int
    }

    /// Version der Plan-Logik. Erhöhen, wenn bestehende Pläne beim nächsten Start neu erstellt werden sollen.
    static let currentVersion = 3

    /// Training nach Ziel-Anteil: Schwimmen ~25 %, Rad ~40 %, Laufen ~35 %.
    static let idealShare: [Discipline: Double] = [.swim: 0.25, .bike: 0.40, .run: 0.35]

    // MARK: - Phasen (vom Wettkampf aus rückwärts)

    static func phase(weeksToRace w: Int, taperWeeks: Int) -> TrainingPhase {
        if w <= 0 { return .race }
        if w <= taperWeeks { return .taper }
        if w <= taperWeeks + 2 { return .peak }
        if w <= taperWeeks + 8 { return .build }
        if w <= taperWeeks + 14 { return .base }
        return .prep
    }

    static func weeks(from start: Date, profile: AthleteProfile) -> [WeekInfo] {
        let firstWeek = start.startOfWeek
        let raceWeek = profile.raceDay.startOfWeek
        let count = max(1, firstWeek.days(until: raceWeek) / 7 + 1)
        let taper = profile.taperWeeks
        return (0..<count).map { i -> WeekInfo in
            let w = count - 1 - i
            let ph = PlanGenerator.phase(weeksToRace: w, taperWeeks: taper)
            // Entlastung alle 4 Wochen (festes Raster vom Wettkampf aus, damit es beim Neu-Erstellen stabil bleibt)
            let loadPhases: [TrainingPhase] = [.prep, .base, .build]
            let isRecovery = loadPhases.contains(ph) && (w - taper - 2) % 4 == 0 && i > 0
            return WeekInfo(start: firstWeek.adding(days: i * 7), phase: ph, isRecovery: isRecovery,
                            weeksToRace: w, taperStep: ph == .taper ? taper - w : 0)
        }
    }

    static func phase(on date: Date, profile: AthleteProfile) -> TrainingPhase {
        let w = max(0, date.startOfWeek.days(until: profile.raceDay.startOfWeek) / 7)
        return phase(weeksToRace: w, taperWeeks: profile.taperWeeks)
    }

    // MARK: - Umfang & Gewichtung

    /// Zielumfang pro Woche in der Spitzenphase (Minuten).
    static func peakMinutes(profile: AthleteProfile) -> Double {
        profile.experience.peakWeeklyMinutes * profile.volumeFactor
    }

    /// Startumfang: bisheriger Umfang (Angabe oder tatsächlich trainiert), mindestens das Minimum des Niveaus.
    static func startMinutes(profile: AthleteProfile, recentWeeklyMinutes: Double) -> Double {
        let current = max(Double(profile.currentWeeklyMinutes), recentWeeklyMinutes)
        let peak = peakMinutes(profile: profile)
        return min(max(current, profile.experience.minimumStartMinutes), peak * 0.8)
    }

    /// Gewicht je Disziplin: Ziel-Anteil, verstärkt für Disziplinen, in denen bisher wenig trainiert wird.
    static func disciplineWeights(profile: AthleteProfile) -> [Discipline: Double] {
        let total = Double(profile.currentWeeklyMinutes)
        var result: [Discipline: Double] = [:]
        for d in Discipline.allCases {
            let ideal = idealShare[d] ?? 0.33
            var deficit = 0.0
            if total > 0 {
                let actualShare = Double(profile.currentMinutes(for: d)) / total
                deficit = max(0, min(1, 1 - actualShare / ideal))
            }
            result[d] = ideal * (1 + 0.6 * deficit)
        }
        return result
    }

    /// Disziplin mit dem größten Nachholbedarf (nil, wenn ausgeglichen oder keine Angaben).
    static func focusDiscipline(profile: AthleteProfile) -> Discipline? {
        guard profile.currentWeeklyMinutes > 0 else { return nil }
        let weights = disciplineWeights(profile: profile)
        let boosted = Discipline.allCases.max { (weights[$0]! / idealShare[$0]!) < (weights[$1]! / idealShare[$1]!) }
        guard let d = boosted, weights[d]! / idealShare[d]! > 1.15 else { return nil }
        return d
    }

    /// Wochenumfang für jede Woche.
    static func weeklyMinutes(weeks: [WeekInfo], start: Double, peak: Double) -> [Double] {
        // Index der ersten Spitzenwoche (oder letzte Woche vor dem Tapering)
        let rampEnd = weeks.firstIndex { $0.phase == .peak || $0.phase == .taper || $0.phase == .race } ?? max(0, weeks.count - 1)
        var result: [Double] = []
        var lastLoad = start
        for (i, week) in weeks.enumerated() {
            var target: Double
            switch week.phase {
            case .taper: target = peak * (week.taperStep == 0 ? 0.6 : 0.45)
            case .race: target = peak * 0.3
            case .peak: target = peak
            default:
                // sanfte Kurve: am Anfang flach, später steiler
                let t = rampEnd > 0 ? Double(i) / Double(rampEnd) : 1
                target = start + (peak - start) * pow(min(1, t), 1.4)
                if week.phase == .prep { target = min(target, peak * 0.6) }
            }
            if week.phase != .taper && week.phase != .race {
                // höchstens ~10 % Steigerung gegenüber der letzten normalen Woche
                target = min(target, lastLoad * 1.10)
                target = max(target, min(start, lastLoad))
                lastLoad = target
            }
            if week.isRecovery { target *= 0.7 }
            result.append(target)
        }
        return result
    }

    // MARK: - Plan erzeugen

    static func generate(from startDate: Date, profile: AthleteProfile, recentWeeklyMinutes: Double = 0) -> [PlannedWorkout] {
        let today = startDate.startOfDay
        let raceDay = profile.raceDay
        guard raceDay > today else { return [] }

        let allWeeks = weeks(from: today, profile: profile)
        let peak = peakMinutes(profile: profile)
        let start = startMinutes(profile: profile, recentWeeklyMinutes: recentWeeklyMinutes)
        let volumes = weeklyMinutes(weeks: allWeeks, start: start, peak: peak)
        let weights = disciplineWeights(profile: profile)
        let experience = profile.experience
        let maxDays = min(7, max(1, profile.trainingDaysPerWeek))
        // Über die Wochen mitgezählt, damit bei wenigen Einheiten pro Woche alle Disziplinen drankommen
        var cumulative: [Discipline: Double] = [.swim: 0, .bike: 0, .run: 0]

        var result: [PlannedWorkout] = []
        for (week, volume) in zip(allWeeks, volumes) {
            if week.phase == .race {
                result += raceWeek(week: week, profile: profile, from: today)
                continue
            }
            let capacity = (0..<7).map { AvailabilityCalculator.planningCapacity(day: week.start.adding(days: $0), profile: profile) }
            let usableDays = capacity.filter { $0 >= 30 }.count
            guard usableDays > 0 else { continue }

            // Anzahl Einheiten aus dem Umfang ableiten
            var sessions = Int((volume / experience.typicalSessionMinutes).rounded())
            sessions = min(max(1, sessions), maxDays, usableDays)

            // Disziplinen verteilen (gewichtet, Sainte-Laguë-artig über alle Wochen)
            var perWeek: [Discipline: Int] = [.swim: 0, .bike: 0, .run: 0]
            var chosen: [SessionKind] = []
            for _ in 0..<sessions {
                let candidates = Discipline.allCases.filter { sessions > 3 || perWeek[$0]! == 0 }
                let pool = candidates.isEmpty ? Discipline.allCases : candidates
                let d = pool.max { a, b in
                    weights[a]! / (cumulative[a]! + Double(perWeek[a]!) * 2 + 1) <
                    weights[b]! / (cumulative[b]! + Double(perWeek[b]!) * 2 + 1)
                }!
                let list = kinds(for: d)
                chosen.append(list[min(perWeek[d]!, list.count - 1)])
                perWeek[d]! += 1
            }
            for d in Discipline.allCases { cumulative[d]! += Double(perWeek[d]!) }

            // Tage zuweisen: lange Einheiten zuerst
            var assigned: [Int: [SessionKind]] = [:]
            for kind in chosen.sorted(by: { ($0.isLong ? 0 : 1) < ($1.isLong ? 0 : 1) }) {
                guard let target = dayFor(kind: kind, capacity: capacity, used: Set(assigned.keys)) else { continue }
                assigned[target] = [kind]
                // Koppellauf nach der langen Radeinheit in Aufbau- und Spitzenphase
                if kind == .bikeLong && (week.phase == .build || week.phase == .peak) && !week.isRecovery && sessions >= 3 {
                    assigned[target]!.append(.brickRun)
                }
            }

            // Umfang auf die Einheiten verteilen
            let totalWeight = assigned.values.flatMap { $0 }.reduce(0) { $0 + $1.weight }
            guard totalWeight > 0 else { continue }
            for (dayIndex, kinds) in assigned {
                let date = week.start.adding(days: dayIndex)
                guard date >= today, date < raceDay else { continue }
                let raw = kinds.map { volume * $0.weight / totalWeight }
                let dayTotal = raw.reduce(0, +)
                let maxMinutes = Double(max(capacity[dayIndex], 20))
                let scale = dayTotal > maxMinutes ? maxMinutes / dayTotal : 1
                for (kind, m) in zip(kinds, raw) {
                    let mins = roundTo5(max(kind == .brickRun ? 10 : 20, m * scale))
                    let level = intensity(for: kind, week: week, experience: experience)
                    let text = describe(kind: kind, phase: week.phase, recovery: week.isRecovery,
                                        minutes: mins, experience: experience)
                    result.append(PlannedWorkout(
                        date: date,
                        discipline: kind.discipline,
                        intensity: level,
                        minutes: mins,
                        distanceKm: estimatedDistance(kind.discipline, minutes: mins, intensity: level, experience: experience),
                        title: text.title,
                        details: text.details,
                        phase: week.phase,
                        isKey: kind.isKey && !week.isRecovery && week.phase != .prep
                    ))
                }
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    /// Löscht zukünftige, noch offene generierte Einheiten und erzeugt den Plan neu.
    @MainActor
    static func regenerate(context: ModelContext, profile: AthleteProfile) {
        let today = Date.now.startOfDay
        let all = (try? context.fetch(FetchDescriptor<PlannedWorkout>())) ?? []
        for w in all where w.isGenerated && w.status == .planned && w.date >= today {
            context.delete(w)
        }
        let completed = (try? context.fetch(FetchDescriptor<CompletedWorkout>())) ?? []
        // Tatsächlicher Umfang der letzten 3 Wochen fließt in den Startumfang ein
        let recent = completed.filter { $0.date >= today.adding(days: -21) }.reduce(0) { $0 + $1.durationMinutes } / 3
        // Wenn heute schon trainiert wurde, ab morgen planen.
        let start = completed.contains(where: { $0.date.isToday }) ? today.adding(days: 1) : today
        for w in generate(from: start, profile: profile, recentWeeklyMinutes: recent) {
            context.insert(w)
        }
        profile.planGeneratedAt = .now
        profile.planVersion = currentVersion
        try? context.save()
    }

    // MARK: - Hilfen

    /// Wählt den Trainingstag: bevorzugter Tag, sonst ein freier Tag mit genug Zeit,
    /// möglichst nicht direkt neben einem anderen Trainingstag.
    private static func dayFor(kind: SessionKind, capacity: [Int], used: Set<Int>) -> Int? {
        let preferred = kind.preferredDay
        let needed = kind.isLong ? 60 : 30
        let free = (0..<7).filter { !used.contains($0) && capacity[$0] >= 30 }
        if free.contains(preferred) && capacity[preferred] >= needed { return preferred }
        let good = free.filter { capacity[$0] >= needed }
        let pool = good.isEmpty ? free : good
        func neighbours(_ d: Int) -> Int { (used.contains(d - 1) ? 1 : 0) + (used.contains(d + 1) ? 1 : 0) }
        if kind.isLong {
            return pool.max { (capacity[$0], -neighbours($0), -abs($0 - preferred)) < (capacity[$1], -neighbours($1), -abs($1 - preferred)) }
        }
        return pool.min { (neighbours($0), abs($0 - preferred), $0) < (neighbours($1), abs($1 - preferred), $1) }
    }

    private static func intensity(for kind: SessionKind, week: WeekInfo, experience: Experience) -> Intensity {
        if week.isRecovery { return kind.isKey || kind == .swimTechnique ? .easy : .recovery }
        let base: Intensity
        switch (week.phase, kind) {
        case (.prep, _): base = .easy
        case (_, .runLong), (_, .swimEndurance), (_, .runEasy): base = .easy
        case (.base, .bikeLong): base = .easy
        case (_, .bikeLong): base = .moderate
        case (.base, .runIntervals): base = .moderate
        case (_, .runIntervals): base = .hard
        case (.base, .swimTechnique): base = .easy
        case (_, .swimTechnique): base = .hard
        case (.base, .bikeTempo): base = .moderate
        case (.taper, .bikeTempo): base = .moderate
        case (_, .bikeTempo): base = .hard
        case (_, .brickRun): base = .moderate
        }
        // Einsteiger: harte Intervalle erst in der Spitzenphase
        if experience == .beginner && base == .hard && week.phase != .peak { return .moderate }
        return base
    }

    static func estimatedDistance(_ d: Discipline, minutes: Int, intensity: Intensity,
                                  experience: Experience = .intermediate) -> Double {
        let speedFactor: Double = (intensity >= .moderate ? 1.07 : 1.0) * experience.speedFactor
        let km = Double(minutes) * d.kmPerMinute * speedFactor
        switch d {
        case .swim: return (km * 20).rounded() / 20          // auf 50 m
        default: return max(1, (km * 2).rounded() / 2)       // auf 0,5 km
        }
    }

    private static func roundTo5(_ m: Double) -> Int { Int((m / 5).rounded()) * 5 }

    // MARK: - Wettkampfwoche

    private static func raceWeek(week: WeekInfo, profile: AthleteProfile, from today: Date) -> [PlannedWorkout] {
        let raceDay = profile.raceDay
        // kurze Aktivierungen an den Tagen -5, -4, -3, -1 vor dem Rennen
        let items: [(offset: Int, d: Discipline, min: Int, title: String, details: String)] = [
            (-5, .swim, 25, "Aktivierung Schwimmen", "10 Min einschwimmen, 4×50 m im Wettkampftempo, locker ausschwimmen. Neo testen, falls erlaubt."),
            (-4, .bike, 45, "Aktivierung Rad", "Locker rollen, darin 3×2 Min im Renntempo. Rad-Check: Reifen, Schaltung, Bremsen."),
            (-3, .run, 25, "Aktivierung Laufen", "Locker traben, 4 Steigerungsläufe à 80 m. Danach Beine hoch."),
            (-1, .run, 15, "Shake-out", "15 Min ganz locker, ein paar kurze Antritte. Wechselzone checken, früh schlafen!"),
        ]
        return items.compactMap { item -> PlannedWorkout? in
            let date = raceDay.adding(days: item.offset)
            guard date >= today, date >= week.start else { return nil }
            return PlannedWorkout(
                date: date, discipline: item.d, intensity: .easy, minutes: item.min,
                distanceKm: estimatedDistance(item.d, minutes: item.min, intensity: .easy),
                title: item.title, details: item.details, phase: .race
            )
        }
    }

    // MARK: - Beschreibungen

    static func describe(kind: SessionKind, phase: TrainingPhase, recovery: Bool, minutes: Int,
                         experience: Experience = .intermediate) -> (title: String, details: String) {
        if phase == .prep {
            switch kind.discipline {
            case .swim:
                if experience == .beginner {
                    return ("Schwimm-Einstieg", "\(minutes) Min: abwechselnd 25–50 m kraulen und 20–30 s Pause am Beckenrand. Fokus: unter Wasser ruhig ausatmen, lang machen. Zwischendurch Brust ist völlig okay.")
                }
                return ("Technik-Schwimmen", "\(minutes) Min locker: Technikübungen (Abschlag, Faustschwimmen) im Wechsel mit ruhigen 100ern. Züge pro Bahn zählen und senken.")
            case .bike:
                return ("Lockere Radrunde", "\(minutes) Min entspannt fahren, Trittfrequenz eher hoch (80–90). Du solltest dich dabei problemlos unterhalten können. Rollentrainer zählt auch.")
            case .run:
                if experience == .beginner {
                    return ("Lauf-Geh-Training", "\(minutes) Min: 5 Min zügig gehen, dann im Wechsel 2 Min locker laufen und 1 Min gehen. Die Laufabschnitte werden mit der Zeit länger. Lieber zu langsam als zu schnell!")
                }
                return ("Lockerer Lauf", "\(minutes) Min im Plauder-Tempo. Am Ende 3–4 kurze Steigerungen, wenn's sich gut anfühlt.")
            }
        }
        if recovery {
            switch kind.discipline {
            case .swim: return ("Lockeres Techniktraining", "Entlastungswoche: \(minutes) Min ruhig schwimmen, Fokus auf langen Zug und Wasserlage. Mit Pullbuoy abwechseln.")
            case .bike: return ("Lockere Ausfahrt", "Entlastungswoche: \(minutes) Min entspannt kurbeln, hohe Trittfrequenz (90+), kein Druck.")
            case .run: return ("Lockerer Lauf", "Entlastungswoche: \(minutes) Min im Plauder-Tempo. Wenn's zwickt: lieber gehen.")
            }
        }
        switch kind {
        case .swimTechnique:
            if phase == .base {
                return ("Technik-Schwimmen", "300 m einschwimmen · 8×50 m Technik (Abschlag, Faustschwimmen, Zählen der Züge) · 6×100 m locker-gleichmäßig, 20 s Pause · 200 m ausschwimmen")
            }
            return ("Schwimm-Intervalle", "300 m einschwimmen · 4×50 m Technik · 8×100 m zügig, 15 s Pause (Ziel: gleiche Zeiten) · 4×50 m schnell · 200 m ausschwimmen")
        case .swimEndurance:
            if phase == .peak || phase == .taper {
                return ("Wettkampf-Schwimmen", "Einschwimmen, dann 3×400 m im Wettkampftempo mit Orientierungsblick (Sighting) alle 6 Züge · locker aus")
            }
            return ("Ausdauer-Schwimmen", "\(minutes) Min gleichmäßig: z. B. 3×500 m locker mit 30 s Pause. Atmung auf 3er-Zug.")
        case .runIntervals:
            switch phase {
            case .base: return ("Tempowechsel-Lauf", "Lockerer Lauf mit schnelleren Abschnitten: 15 Min einlaufen · 6× 2 Min zügig, dazwischen je 2 Min locker traben · 10 Min auslaufen. Macht schneller, ohne zu überfordern.")
            case .build: return ("Lauf-Intervalle", "15 Min einlaufen · 5×1000 m im 10-km-Tempo, 2 Min Trabpause · 10 Min auslaufen")
            case .peak: return ("Tempolauf", "15 Min einlaufen · 2×12 Min im Wettkampftempo, 3 Min Trab · auslaufen")
            default: return ("Lockerer Lauf mit Steigerungen", "Locker laufen, am Ende 4 Steigerungen à 100 m (langsam schneller werden bis fast Sprint).")
            }
        case .runLong:
            return ("Langer Lauf", "\(minutes) Min ruhig im Grundlagentempo (du kannst noch reden). Verpflegung testen.")
        case .runEasy:
            return ("Lockerer Lauf", "\(minutes) Min locker")
        case .bikeTempo:
            switch phase {
            case .base: return ("Rad zügig", "15 Min einrollen · 3×10 Min zügig (GA2), 5 Min locker dazwischen · ausrollen")
            case .taper: return ("Rad mit Renntempo", "Einrollen · 3×5 Min Renntempo · locker ausrollen")
            default: return ("Rad-Intervalle", "15 Min einrollen · 4×8 Min hart an der Schwelle, 4 Min locker · ausrollen. Gut auf dem Rollentrainer machbar.")
            }
        case .bikeLong:
            if phase == .base {
                return ("Lange Ausfahrt", "\(minutes) Min gleichmäßig locker, Trittfrequenz 85–95. Alle 20 Min trinken, alle 45 Min essen.")
            }
            return ("Lange Ausfahrt mit Renntempo", "\(minutes) Min, darin 2–3 Blöcke à 15 Min im Wettkampftempo in Aero-Position. Verpflegung wie im Rennen.")
        case .brickRun:
            return ("Koppellauf", "Direkt nach dem Rad: \(minutes) Min laufen, die ersten 5 Min bewusst locker, dann ins Wettkampftempo. Wechsel üben!")
        }
    }

    /// Erwartete XP aller geplanten Einheiten (Basis für das Leveling).
    static func plannedXP(_ planned: [PlannedWorkout]) -> Double {
        planned.reduce(0) { $0 + Double($1.minutes) * $1.intensity.xpFactor + 20 }
    }
}
