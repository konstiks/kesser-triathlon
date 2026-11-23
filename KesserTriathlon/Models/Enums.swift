import SwiftUI

/// Die drei Triathlon-Disziplinen.
enum Discipline: String, Codable, CaseIterable, Identifiable {
    case swim, bike, run

    var id: String { rawValue }

    var name: String {
        switch self {
        case .swim: return "Schwimmen"
        case .bike: return "Radfahren"
        case .run: return "Laufen"
        }
    }

    var shortName: String {
        switch self {
        case .swim: return "Schwimmen"
        case .bike: return "Rad"
        case .run: return "Laufen"
        }
    }

    var symbol: String {
        switch self {
        case .swim: return "figure.pool.swim"
        case .bike: return "figure.outdoor.cycle"
        case .run: return "figure.run"
        }
    }

    var color: Color {
        switch self {
        case .swim: return Color(red: 0.13, green: 0.55, blue: 0.95)
        case .bike: return Color(red: 0.98, green: 0.55, blue: 0.12)
        case .run: return Color(red: 0.20, green: 0.75, blue: 0.40)
        }
    }

    /// Grobe Durchschnittsgeschwindigkeit in km pro Minute (für Distanz-Schätzungen im Plan).
    var kmPerMinute: Double {
        switch self {
        case .swim: return 0.04   // ca. 2:30 min / 100 m
        case .bike: return 0.43   // ca. 26 km/h
        case .run: return 0.16    // ca. 6:15 min / km
        }
    }

    /// Bild-Asset für Pixel-Konsti im Outfit dieser Disziplin.
    var standingSprite: String {
        switch self {
        case .swim: return "konsti_swim_stand"
        case .bike: return "konsti_bike_stand"
        case .run: return "konsti_run_action"
        }
    }

    var actionSprite: String {
        switch self {
        case .swim: return "konsti_swim_action"
        case .bike: return "konsti_bike_action"
        case .run: return "konsti_run_action"
        }
    }

    func formatDistance(_ km: Double) -> String {
        if self == .swim {
            return "\(Int((km * 1000).rounded())) m"
        }
        return String(format: km < 10 ? "%.1f km" : "%.0f km", km)
    }
}

/// Trainingsintensität.
enum Intensity: Int, Codable, CaseIterable, Identifiable, Comparable {
    case recovery = 0, easy, moderate, hard

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .recovery: return "Regeneration"
        case .easy: return "Locker (GA1)"
        case .moderate: return "Zügig (GA2)"
        case .hard: return "Intervalle"
        }
    }

    var shortName: String {
        switch self {
        case .recovery: return "Regeneration"
        case .easy: return "Locker"
        case .moderate: return "Zügig"
        case .hard: return "Hart"
        }
    }

    var color: Color {
        switch self {
        case .recovery: return .teal
        case .easy: return .green
        case .moderate: return .orange
        case .hard: return .red
        }
    }

    /// Faktor für Erfahrungspunkte.
    var xpFactor: Double {
        switch self {
        case .recovery: return 0.8
        case .easy: return 1.0
        case .moderate: return 1.25
        case .hard: return 1.5
        }
    }

    static func < (lhs: Intensity, rhs: Intensity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Ampel für Stimmung und gefühlte Schwere.
enum Ampel: Int, Codable, CaseIterable, Identifiable {
    case green = 0, yellow, red

    var id: Int { rawValue }

    var color: Color {
        switch self {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }

    var moodLabel: String {
        switch self {
        case .green: return "Top drauf"
        case .yellow: return "Geht so"
        case .red: return "Mies"
        }
    }

    var effortLabel: String {
        switch self {
        case .green: return "Leicht"
        case .yellow: return "Fordernd"
        case .red: return "Am Limit"
        }
    }
}

enum WorkoutStatus: String, Codable {
    case planned, done, skipped

    var name: String {
        switch self {
        case .planned: return "Geplant"
        case .done: return "Erledigt"
        case .skipped: return "Ausgelassen"
        }
    }
}

enum WorkoutSource: String, Codable {
    case manual, health

    var name: String {
        switch self {
        case .manual: return "Manuell"
        case .health: return "Apple Health"
        }
    }
}

/// Trainingsphase im Plan.
enum TrainingPhase: String, Codable {
    case prep, base, build, peak, taper, race

    var name: String {
        switch self {
        case .prep: return "Einstiegs-Phase"
        case .base: return "Grundlagen-Phase"
        case .build: return "Aufbau-Phase"
        case .peak: return "Spitzen-Phase"
        case .taper: return "Tapering"
        case .race: return "Wettkampfwoche"
        }
    }

    var explanation: String {
        switch self {
        case .prep: return "Sanft starten: wenige, kurze und lockere Einheiten. Gewohnheit aufbauen, Technik lernen, Umfang langsam steigern."
        case .base: return "Ausdauer-Fundament legen: viel locker, Technik sauber."
        case .build: return "Umfang und Intervalle steigen. Jetzt wird's kess."
        case .peak: return "Wettkampfnah trainieren: Koppeleinheiten und Renntempo."
        case .taper: return "Umfang runter, Spritzigkeit behalten. Frisch an den Start!"
        case .race: return "Nur noch kurze Aktivierung. Vertrau dem Training."
        }
    }
}

/// Wettkampf-Distanzen.
enum RaceType: String, Codable, CaseIterable, Identifiable {
    case volks, sprint, olympic, middle, long, custom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .volks: return "Volksdistanz"
        case .sprint: return "Sprintdistanz"
        case .olympic: return "Olympische Distanz"
        case .middle: return "Mitteldistanz (70.3)"
        case .long: return "Langdistanz"
        case .custom: return "Eigene Distanzen"
        }
    }

    /// Schwimmen, Rad, Laufen in km.
    var distances: (swim: Double, bike: Double, run: Double)? {
        switch self {
        case .volks: return (0.5, 20, 5)
        case .sprint: return (0.75, 20, 5)
        case .olympic: return (1.5, 40, 10)
        case .middle: return (1.9, 90, 21.1)
        case .long: return (3.8, 180, 42.2)
        case .custom: return nil
        }
    }

    /// Skaliert die Länge der Trainingseinheiten.
    var volumeFactor: Double {
        switch self {
        case .volks: return 0.75
        case .sprint: return 0.85
        case .olympic: return 1.0
        case .middle: return 1.35
        case .long: return 1.7
        case .custom: return 1.0
        }
    }

    /// Wie viele Wochen Tapering (ohne Wettkampfwoche).
    var taperWeeks: Int {
        switch self {
        case .volks, .sprint, .olympic, .custom: return 1
        case .middle, .long: return 2
        }
    }
}

/// Trainingserfahrung, steuert Umfang, Intensität und Tempo-Schätzungen.
enum Experience: String, Codable, CaseIterable, Identifiable {
    case beginner, intermediate, advanced

    var id: String { rawValue }

    var name: String {
        switch self {
        case .beginner: return "Einsteiger"
        case .intermediate: return "Fortgeschritten"
        case .advanced: return "Profi"
        }
    }

    var explanation: String {
        switch self {
        case .beginner: return "Erster Triathlon, bisher wenig oder unregelmäßig Ausdauersport."
        case .intermediate: return "Regelmäßig Ausdauersport, vielleicht schon Lauf- oder Radevents."
        case .advanced: return "Viel Erfahrung, hoher Trainingsumfang, Wettkämpfe gewohnt."
        }
    }

    var symbol: String {
        switch self {
        case .beginner: return "tortoise.fill"
        case .intermediate: return "figure.run"
        case .advanced: return "hare.fill"
        }
    }

    /// Wochenumfang (Minuten) in der Spitzenphase für die olympische Distanz.
    /// Orientiert an gängigen Plänen: Sprint-Einsteiger ca. 4–6 h, Fortgeschrittene 6–8 h, Ambitionierte 8–10 h.
    var peakWeeklyMinutes: Double {
        switch self {
        case .beginner: return 300
        case .intermediate: return 450
        case .advanced: return 660
        }
    }

    /// Startumfang pro Woche, wenn bisher kaum trainiert wird.
    var minimumStartMinutes: Double {
        switch self {
        case .beginner: return 60
        case .intermediate: return 100
        case .advanced: return 150
        }
    }

    /// Typische Dauer einer Einheit (bestimmt, wie viele Einheiten pro Woche sinnvoll sind).
    var typicalSessionMinutes: Double {
        switch self {
        case .beginner: return 35
        case .intermediate: return 45
        case .advanced: return 55
        }
    }

    /// Tempo-Faktor gegenüber den Standardwerten.
    var speedFactor: Double {
        switch self {
        case .beginner: return 0.85
        case .intermediate: return 1.0
        case .advanced: return 1.12
        }
    }
}
