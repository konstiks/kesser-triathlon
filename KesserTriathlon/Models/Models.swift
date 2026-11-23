import Foundation
import SwiftData

/// Persönliche Einstellungen: Wettkampf, Verfügbarkeit, Verbindungen.
@Model
final class AthleteProfile {
    var name: String = "Konsti"
    var raceName: String = "Köln-Triathlon"
    var raceDate: Date = Calendar.de.date(from: DateComponents(year: 2027, month: 9, day: 5)) ?? .now
    var raceTypeRaw: String = RaceType.custom.rawValue
    var swimKm: Double = 1.4
    var bikeKm: Double = 20
    var runKm: Double = 4.8

    /// Feste Ruhetage (an denen nie trainiert wird), 0 = Montag … 6 = Sonntag.
    var restDays: [Int] = []
    /// Gewünschte Trainingstage pro Woche (3–7).
    var trainingDaysPerWeek: Int = 4
    /// Arbeitstage (0 = Montag …) und Arbeitszeit in Minuten ab Mitternacht.
    var workDays: [Int] = [0, 1, 2, 3, 4]
    var workStartMinutes: Int = 8 * 60
    var workEndMinutes: Int = 17 * 60
    /// Maximale Trainingszeit an Werktagen bzw. am Wochenende (Minuten).
    var weekdayMaxMinutes: Int = 75
    var weekendMaxMinutes: Int = 180
    /// Zeitfenster, in dem trainiert werden kann.
    var dayStartHour: Int = 6
    var dayEndHour: Int = 21
    /// Version der Plan-Logik, mit der der Plan erstellt wurde (für automatische Updates).
    var planVersion: Int = 1

    var useCalendar: Bool = false
    var healthConnected: Bool = false
    var healthImportStart: Date = Calendar.de.date(byAdding: .day, value: -14, to: .now) ?? .now
    var lastHealthSync: Date?
    /// In der App gelöschte Health-Workouts, die nicht erneut importiert werden sollen.
    var ignoredHealthIDs: [String] = []

    /// Bereits gefeierte Cheerleader-Ereignisse.
    var seenCheerIDs: [String] = []

    var onboardingDone: Bool = false
    var planGeneratedAt: Date?

    init() {}

    var raceType: RaceType {
        get { RaceType(rawValue: raceTypeRaw) ?? .olympic }
        set {
            raceTypeRaw = newValue.rawValue
            if let d = newValue.distances {
                swimKm = d.swim
                bikeKm = d.bike
                runKm = d.run
            }
        }
    }

    func raceDistance(for discipline: Discipline) -> Double {
        switch discipline {
        case .swim: return swimKm
        case .bike: return bikeKm
        case .run: return runKm
        }
    }

    var volumeFactor: Double {
        if raceType != .custom { return raceType.volumeFactor }
        switch bikeKm {
        case ..<22: return 0.8
        case ..<50: return 1.0
        case ..<110: return 1.35
        default: return 1.7
        }
    }

    var taperWeeks: Int { bikeKm >= 80 ? 2 : 1 }

    /// Persönliches Zeitbudget eines Tages (0 an festen Ruhetagen).
    func maxMinutes(on day: Date) -> Int {
        if restDays.contains(day.weekdayIndex) { return 0 }
        return day.weekdayIndex >= 5 ? weekendMaxMinutes : weekdayMaxMinutes
    }

    func isWorkDay(_ day: Date) -> Bool { workDays.contains(day.weekdayIndex) }

    /// Arbeitszeit an diesem Tag (nil, wenn kein Arbeitstag).
    func workInterval(on day: Date) -> DateInterval? {
        guard isWorkDay(day), workEndMinutes > workStartMinutes else { return nil }
        let start = day.startOfDay.addingTimeInterval(TimeInterval(workStartMinutes * 60))
        let end = day.startOfDay.addingTimeInterval(TimeInterval(workEndMinutes * 60))
        return DateInterval(start: start, end: end)
    }

    var workTimeText: String {
        func t(_ m: Int) -> String { String(format: "%d:%02d", m / 60, m % 60) }
        return "\(t(workStartMinutes))–\(t(workEndMinutes)) Uhr"
    }

    var raceDay: Date { raceDate.startOfDay }

    var daysUntilRace: Int {
        Calendar.de.dateComponents([.day], from: Date.now.startOfDay, to: raceDay).day ?? 0
    }
}

/// Eine geplante Trainingseinheit.
@Model
final class PlannedWorkout {
    var id: UUID = UUID()
    var date: Date = Date.now.startOfDay
    var disciplineRaw: String = Discipline.run.rawValue
    var intensityRaw: Int = Intensity.easy.rawValue
    var minutes: Int = 45
    var distanceKm: Double = 0
    var title: String = ""
    var details: String = ""
    var statusRaw: String = WorkoutStatus.planned.rawValue
    var phaseRaw: String = TrainingPhase.base.rawValue
    /// Schlüsseleinheit (lange Einheit / Intervalle), die nicht ausfallen sollte.
    var isKey: Bool = false
    /// Ursprüngliches Datum, falls verschoben.
    var originalDate: Date?
    var completedID: UUID?
    /// Vom Planer erzeugt (wird beim Neu-Generieren ersetzt) oder selbst angelegt.
    var isGenerated: Bool = true

    init(date: Date, discipline: Discipline, intensity: Intensity, minutes: Int,
         distanceKm: Double = 0, title: String, details: String = "",
         phase: TrainingPhase = .base, isKey: Bool = false, isGenerated: Bool = true) {
        self.id = UUID()
        self.date = date.startOfDay
        self.disciplineRaw = discipline.rawValue
        self.intensityRaw = intensity.rawValue
        self.minutes = minutes
        self.distanceKm = distanceKm
        self.title = title
        self.details = details
        self.phaseRaw = phase.rawValue
        self.isKey = isKey
        self.isGenerated = isGenerated
    }

    var discipline: Discipline {
        get { Discipline(rawValue: disciplineRaw) ?? .run }
        set { disciplineRaw = newValue.rawValue }
    }

    var intensity: Intensity {
        get { Intensity(rawValue: intensityRaw) ?? .easy }
        set { intensityRaw = newValue.rawValue }
    }

    var status: WorkoutStatus {
        get { WorkoutStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    var phase: TrainingPhase {
        get { TrainingPhase(rawValue: phaseRaw) ?? .base }
        set { phaseRaw = newValue.rawValue }
    }

    var wasMoved: Bool {
        guard let originalDate else { return false }
        return !originalDate.isSameDay(as: date)
    }

    var isOverdue: Bool { status == .planned && date < Date.now.startOfDay }

    /// "Mittwoch" (innerhalb einer Woche) bzw. "Mi., 3. Dez."
    var weekdayText: String {
        abs(Date.now.days(until: date)) < 7 ? date.weekdayName : date.shortDayText
    }
}

/// Ein absolviertes Training (manuell eingetragen oder aus Apple Health).
@Model
final class CompletedWorkout {
    var id: UUID = UUID()
    var date: Date = Date.now
    var disciplineRaw: String = Discipline.run.rawValue
    var durationMinutes: Double = 0
    var distanceKm: Double = 0
    var avgHeartRate: Double?
    var calories: Double?
    /// Ampel Stimmung (nil = noch nicht bewertet).
    var moodRaw: Int?
    /// Ampel gefühlte Schwere (nil = noch nicht bewertet).
    var effortRaw: Int?
    var notes: String = ""
    var sourceRaw: String = WorkoutSource.manual.rawValue
    var healthKitID: String?
    var plannedID: UUID?
    /// Intensität der verknüpften Planeinheit (für XP).
    var plannedIntensityRaw: Int?

    init(date: Date, discipline: Discipline, durationMinutes: Double, distanceKm: Double,
         source: WorkoutSource = .manual) {
        self.id = UUID()
        self.date = date
        self.disciplineRaw = discipline.rawValue
        self.durationMinutes = durationMinutes
        self.distanceKm = distanceKm
        self.sourceRaw = source.rawValue
    }

    var discipline: Discipline {
        get { Discipline(rawValue: disciplineRaw) ?? .run }
        set { disciplineRaw = newValue.rawValue }
    }

    var mood: Ampel? {
        get { moodRaw.flatMap(Ampel.init(rawValue:)) }
        set { moodRaw = newValue?.rawValue }
    }

    var effort: Ampel? {
        get { effortRaw.flatMap(Ampel.init(rawValue:)) }
        set { effortRaw = newValue?.rawValue }
    }

    var source: WorkoutSource {
        get { WorkoutSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var isRated: Bool { mood != nil && effort != nil }

    /// Pace bzw. Geschwindigkeit als Text.
    var paceText: String? {
        guard distanceKm > 0, durationMinutes > 0 else { return nil }
        switch discipline {
        case .swim:
            let secPer100 = durationMinutes * 60 / (distanceKm * 10)
            return String(format: "%d:%02d /100 m", Int(secPer100) / 60, Int(secPer100) % 60)
        case .bike:
            return String(format: "%.1f km/h", distanceKm / (durationMinutes / 60))
        case .run:
            let secPerKm = durationMinutes * 60 / distanceKm
            return String(format: "%d:%02d /km", Int(secPerKm) / 60, Int(secPerKm) % 60)
        }
    }
}
