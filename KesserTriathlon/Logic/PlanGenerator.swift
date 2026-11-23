import Foundation
import SwiftData

/// Erzeugt einen periodisierten Trainingsplan von heute bis zum Wettkampf.
///
/// Aufbau: Grundlage → Aufbau → Spitze → Tapering → Wettkampfwoche.
/// In Grundlagen- und Aufbauphase ist jede 4. Woche eine Entlastungswoche.
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

        /// Basisdauer in Minuten für die olympische Distanz in der Aufbauphase.
        var baseMinutes: Double {
            switch self {
            case .swimTechnique: return 45
            case .swimEndurance: return 50
            case .runIntervals: return 50
            case .runLong: return 75
            case .runEasy: return 40
            case .bikeTempo: return 70
            case .bikeLong: return 120
            case .brickRun: return 20
            }
        }

        var isKey: Bool {
            switch self {
            case .runLong, .bikeLong, .runIntervals: return true
            default: return false
            }
        }
    }

    struct WeekInfo {
        let start: Date
        let phase: TrainingPhase
        let isRecovery: Bool
        let factor: Double
        let taperStep: Int
    }

    /// Version der Plan-Logik. Erhöhen, wenn bestehende Pläne beim nächsten Start neu erstellt werden sollen.
    static let currentVersion = 2

    /// Einheiten nach Wichtigkeit mit bevorzugtem Wochentag (0 = Montag).
    /// Bei N Trainingstagen pro Woche werden die ersten N genommen, jede an einem eigenen Tag.
    static let sessionPriority: [(kind: SessionKind, day: Int)] = [
        (.swimTechnique, 1),   // Di
        (.bikeLong, 5),        // Sa
        (.runLong, 6),         // So
        (.runIntervals, 3),    // Do
        (.swimEndurance, 4),   // Fr
        (.bikeTempo, 2),       // Mi
        (.runEasy, 0),         // Mo
    ]

    // MARK: - Phasen

    static func weeks(from start: Date, profile: AthleteProfile) -> [WeekInfo] {
        let firstWeek = start.startOfWeek
        let raceWeek = profile.raceDay.startOfWeek
        let count = max(1, firstWeek.days(until: raceWeek) / 7 + 1)
        let taper = min(profile.taperWeeks, max(0, count - 1))
        let remaining = max(0, count - 1 - taper)
        var peak = remaining >= 4 ? max(1, Int((Double(remaining) * 0.2).rounded())) : 0
        var build = remaining >= 3 ? Int((Double(remaining) * 0.4).rounded()) : remaining
        if remaining < 3 { peak = 0 }
        build = min(build, remaining - peak)
        let base = max(0, remaining - peak - build)

        var result: [WeekInfo] = []
        for i in 0..<count {
            let weekStart = firstWeek.adding(days: i * 7)
            let phase: TrainingPhase
            var indexInPhase = 0
            var phaseLength = 1
            var taperStep = 0
            if i == count - 1 {
                phase = .race
            } else if i >= count - 1 - taper {
                phase = .taper
                taperStep = i - (count - 1 - taper)
            } else if i < base {
                phase = .base; indexInPhase = i; phaseLength = base
            } else if i < base + build {
                phase = .build; indexInPhase = i - base; phaseLength = build
            } else {
                phase = .peak; indexInPhase = i - base - build; phaseLength = peak
            }

            let isRecovery = (phase == .base || phase == .build) && indexInPhase % 4 == 3
            let ramp = phaseLength > 1 ? Double(indexInPhase) / Double(phaseLength - 1) : 0.5
            var factor: Double
            switch phase {
            case .base: factor = 0.75 + 0.15 * ramp
            case .build: factor = 0.92 + 0.15 * ramp
            case .peak: factor = 1.08
            case .taper: factor = taperStep == 0 ? (taper > 1 ? 0.7 : 0.6) : 0.5
            case .race: factor = 0.35
            }
            if isRecovery { factor *= 0.7 }
            result.append(WeekInfo(start: weekStart, phase: phase, isRecovery: isRecovery, factor: factor, taperStep: taperStep))
        }
        return result
    }

    static func phase(on date: Date, profile: AthleteProfile) -> TrainingPhase {
        if date >= profile.raceDay.startOfWeek { return .race }
        let start = (profile.planGeneratedAt ?? date).startOfWeek
        let all = weeks(from: min(start, date), profile: profile)
        return all.first(where: { $0.start.isSameDay(as: date.startOfWeek) })?.phase ?? .base
    }

    // MARK: - Plan erzeugen

    static func generate(from startDate: Date, profile: AthleteProfile) -> [PlannedWorkout] {
        let today = startDate.startOfDay
        let raceDay = profile.raceDay
        guard raceDay > today else { return [] }

        var result: [PlannedWorkout] = []
        for week in weeks(from: today, profile: profile) {
            if week.phase == .race {
                result += raceWeek(week: week, profile: profile, from: today)
                continue
            }
            // N Einheiten auf N verschiedene Tage verteilen (Ruhetage und Arbeitszeit berücksichtigt)
            let capacity = (0..<7).map { AvailabilityCalculator.planningCapacity(day: week.start.adding(days: $0), profile: profile) }
            let count = min(7, max(3, profile.trainingDaysPerWeek))
            var assigned: [Int: [SessionKind]] = [:]
            for (kind, preferred) in sessionPriority.prefix(count) {
                guard let target = dayFor(kind: kind, preferred: preferred, capacity: capacity, used: Set(assigned.keys)) else { continue }
                assigned[target] = [kind]
                // Koppeltraining nach der langen Radeinheit in Aufbau- und Spitzenphase
                if kind == .bikeLong && (week.phase == .build || week.phase == .peak) && !week.isRecovery {
                    assigned[target, default: []].append(.brickRun)
                }
            }
            for (dayIndex, kinds) in assigned {
                let date = week.start.adding(days: dayIndex)
                guard date >= today, date < raceDay else { continue }
                let maxMinutes = Double(max(capacity[dayIndex], 20))
                // gesamte Tagesdauer auf das Tagesbudget begrenzen
                let raw = kinds.map { minutes(for: $0, week: week, profile: profile) }
                let total = raw.reduce(0, +)
                let scale = total > maxMinutes ? maxMinutes / total : 1
                for (kind, m) in zip(kinds, raw) {
                    let mins = roundTo5(max(15, m * scale))
                    let intensity = intensity(for: kind, week: week)
                    let text = describe(kind: kind, phase: week.phase, recovery: week.isRecovery, minutes: mins)
                    let w = PlannedWorkout(
                        date: date,
                        discipline: kind.discipline,
                        intensity: intensity,
                        minutes: mins,
                        distanceKm: estimatedDistance(kind.discipline, minutes: mins, intensity: intensity),
                        title: text.title,
                        details: text.details,
                        phase: week.phase,
                        isKey: kind.isKey && !week.isRecovery
                    )
                    result.append(w)
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
        // Wenn heute schon trainiert wurde, ab morgen planen.
        let completed = (try? context.fetch(FetchDescriptor<CompletedWorkout>())) ?? []
        let start = completed.contains(where: { $0.date.isToday }) ? today.adding(days: 1) : today
        for w in generate(from: start, profile: profile) {
            context.insert(w)
        }
        profile.planGeneratedAt = .now
        profile.planVersion = currentVersion
        try? context.save()
    }

    // MARK: - Hilfen

    /// Wählt den Trainingstag: bevorzugter Tag, sonst der nächstgelegene freie Tag mit genug Zeit.
    /// Lange Einheiten gehen bevorzugt an den Tag mit der meisten freien Zeit.
    private static func dayFor(kind: SessionKind, preferred: Int, capacity: [Int], used: Set<Int>) -> Int? {
        let needed = kind == .bikeLong || kind == .runLong ? 60 : 30
        let free = (0..<7).filter { !used.contains($0) && capacity[$0] >= 30 }
        if free.contains(preferred) && capacity[preferred] >= needed { return preferred }
        let good = free.filter { capacity[$0] >= needed }
        let pool = good.isEmpty ? free : good
        if kind == .bikeLong || kind == .runLong {
            return pool.max { (capacity[$0], -abs($0 - preferred)) < (capacity[$1], -abs($1 - preferred)) }
        }
        return pool.min { (abs($0 - preferred), $0) < (abs($1 - preferred), $1) }
    }

    private static func minutes(for kind: SessionKind, week: WeekInfo, profile: AthleteProfile) -> Double {
        var factor = week.factor
        // Lange Einheiten skalieren stärker mit der Wettkampfdistanz
        switch kind {
        case .bikeLong, .runLong: factor *= profile.volumeFactor
        case .brickRun: factor *= max(1, profile.volumeFactor * 0.9)
        default: factor *= 1 + (profile.volumeFactor - 1) * 0.5
        }
        return kind.baseMinutes * factor
    }

    private static func intensity(for kind: SessionKind, week: WeekInfo) -> Intensity {
        if week.isRecovery { return kind == .swimTechnique ? .easy : (kind.isKey ? .easy : .recovery) }
        switch (week.phase, kind) {
        case (_, .runLong), (_, .swimEndurance), (_, .runEasy): return .easy
        case (.base, .bikeLong): return .easy
        case (_, .bikeLong): return .moderate
        case (.base, .runIntervals): return .moderate
        case (_, .runIntervals): return .hard
        case (.base, .swimTechnique): return .easy
        case (_, .swimTechnique): return .hard
        case (.base, .bikeTempo): return .moderate
        case (.taper, .bikeTempo): return .moderate
        case (_, .bikeTempo): return .hard
        case (_, .brickRun): return .moderate
        }
    }

    static func estimatedDistance(_ d: Discipline, minutes: Int, intensity: Intensity) -> Double {
        let speedFactor: Double = intensity >= .moderate ? 1.07 : 1.0
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

    static func describe(kind: SessionKind, phase: TrainingPhase, recovery: Bool, minutes: Int) -> (title: String, details: String) {
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
