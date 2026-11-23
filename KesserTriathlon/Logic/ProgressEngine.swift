import SwiftUI

/// Die vier Stufen von Pixel-Konsti.
enum Tier: Int, CaseIterable, Comparable {
    case frischling = 0, durchhalter, ass, kesser

    var name: String {
        switch self {
        case .frischling: return "Frischling"
        case .durchhalter: return "Durchhalter"
        case .ass: return "Ausdauer-Ass"
        case .kesser: return "Kesser Konsti"
        }
    }

    var motto: String {
        switch self {
        case .frischling: return "Jeder Kilometer zählt. Los geht's!"
        case .durchhalter: return "Dranbleiben zahlt sich aus."
        case .ass: return "Die Form stimmt. Jetzt nicht nachlassen!"
        case .kesser: return "Bereit für die Ziellinie. Kess wie nie!"
        }
    }

    var color: Color {
        switch self {
        case .frischling: return .gray
        case .durchhalter: return Color(red: 0.80, green: 0.50, blue: 0.20)   // Bronze
        case .ass: return Color(red: 0.62, green: 0.68, blue: 0.75)          // Silber
        case .kesser: return Color(red: 0.98, green: 0.76, blue: 0.10)       // Gold
        }
    }

    var symbol: String {
        switch self {
        case .frischling: return "leaf.fill"
        case .durchhalter: return "flame.fill"
        case .ass: return "bolt.fill"
        case .kesser: return "crown.fill"
        }
    }

    static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }

    static func forReadiness(_ r: Double) -> Tier {
        switch r {
        case ..<0.3: return .frischling
        case ..<0.55: return .durchhalter
        case ..<0.8: return .ass
        default: return .kesser
        }
    }
}

struct LevelInfo {
    static let maxLevel = 20
    let level: Int
    let xp: Int
    let levelStartXP: Int
    let nextLevelXP: Int

    var tier: Tier { Tier(rawValue: min(3, (level - 1) / 5)) ?? .frischling }
    var fractionInLevel: Double {
        guard nextLevelXP > levelStartXP else { return 1 }
        return min(1, max(0, Double(xp - levelStartXP) / Double(nextLevelXP - levelStartXP)))
    }
    var isMax: Bool { level >= LevelInfo.maxLevel }
}

struct DisciplineProgress: Identifiable {
    let discipline: Discipline
    var id: String { discipline.rawValue }
    /// Längste Einheit der letzten 6 Wochen (km).
    let longestKm: Double
    /// Zielwert für die längste Einheit (km).
    let targetKm: Double
    /// Minuten in den letzten 28 Tagen (absolviert / geplant).
    let minutes28: Double
    let plannedMinutes28: Double
    let totalKm: Double
    let xp: Int

    var distanceScore: Double { targetKm > 0 ? min(1, longestKm / targetKm) : 0 }
    var consistency: Double {
        if plannedMinutes28 <= 0 { return minutes28 > 0 ? 1 : 0 }
        return min(1, minutes28 / plannedMinutes28)
    }
    /// Wettkampfbereitschaft 0…1
    var readiness: Double { 0.6 * distanceScore + 0.4 * consistency }
    var tier: Tier { Tier.forReadiness(readiness) }
}

enum ProgressEngine {

    static func xp(for workout: CompletedWorkout) -> Int {
        let intensityFactor: Double
        if let raw = workout.plannedIntensityRaw, let i = Intensity(rawValue: raw) {
            intensityFactor = i.xpFactor
        } else {
            switch workout.effort {
            case .some(.red): intensityFactor = Intensity.hard.xpFactor
            case .some(.yellow): intensityFactor = Intensity.moderate.xpFactor
            default: intensityFactor = Intensity.easy.xpFactor
            }
        }
        let planBonus = workout.plannedID != nil ? 20.0 : 10.0
        return Int(workout.durationMinutes * intensityFactor + planBonus)
    }

    /// Level 1–20. Wer den Plan komplett durchzieht, erreicht am Wettkampftag Level 20.
    static func level(completed: [CompletedWorkout], planned: [PlannedWorkout]) -> LevelInfo {
        let xp = completed.reduce(0) { $0 + self.xp(for: $1) }
        let total = max(3000, PlanGenerator.plannedXP(planned)) * 0.95
        func threshold(_ level: Int) -> Int {
            Int(total * pow(Double(level - 1) / Double(LevelInfo.maxLevel - 1), 1.2))
        }
        var level = 1
        while level < LevelInfo.maxLevel && xp >= threshold(level + 1) { level += 1 }
        let next = level < LevelInfo.maxLevel ? threshold(level + 1) : threshold(level)
        return LevelInfo(level: level, xp: xp, levelStartXP: threshold(level), nextLevelXP: next)
    }

    static func progress(for discipline: Discipline, completed: [CompletedWorkout], planned: [PlannedWorkout],
                         profile: AthleteProfile, now: Date = .now) -> DisciplineProgress {
        let mine = completed.filter { $0.discipline == discipline }
        let d42 = now.adding(days: -42)
        let d28 = now.adding(days: -28)
        let longest = mine.filter { $0.date >= d42 }.map(\.distanceKm).max() ?? 0
        let longFactor: Double = (discipline != .swim && profile.bikeKm >= 80) ? 0.8 : 1.0
        let target = profile.raceDistance(for: discipline) * longFactor
        let minutes28 = mine.filter { $0.date >= d28 }.reduce(0) { $0 + $1.durationMinutes }
        let planned28 = planned
            .filter { $0.discipline == discipline && $0.date >= d28.startOfDay && $0.date < now.startOfDay.adding(days: 1) }
            .reduce(0) { $0 + Double($1.minutes) }
        return DisciplineProgress(
            discipline: discipline,
            longestKm: longest,
            targetKm: target,
            minutes28: minutes28,
            plannedMinutes28: planned28,
            totalKm: mine.reduce(0) { $0 + $1.distanceKm },
            xp: mine.reduce(0) { $0 + xp(for: $1) }
        )
    }

    static func allProgress(completed: [CompletedWorkout], planned: [PlannedWorkout], profile: AthleteProfile) -> [DisciplineProgress] {
        Discipline.allCases.map { progress(for: $0, completed: completed, planned: planned, profile: profile) }
    }

    /// Minuten der letzten n Tage.
    static func minutes(lastDays n: Int, completed: [CompletedWorkout], now: Date = .now) -> Double {
        let from = now.adding(days: -n)
        return completed.filter { $0.date >= from }.reduce(0) { $0 + $1.durationMinutes }
    }
}
