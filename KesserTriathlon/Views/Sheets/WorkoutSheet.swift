import SwiftUI

/// Alle Sheets rund um Trainings an einer Stelle.
enum WorkoutSheet: Identifiable {
    case log(planned: PlannedWorkout?, discipline: Discipline?, minutes: Int?)
    case edit(CompletedWorkout)
    case move(PlannedWorkout, suggested: Date?)
    case editPlanned(PlannedWorkout)
    case newPlanned(Date)

    var id: String {
        switch self {
        case .log(let p, let d, _): return "log-\(p?.id.uuidString ?? d?.rawValue ?? "free")"
        case .edit(let w): return "edit-\(w.id)"
        case .move(let p, _): return "move-\(p.id)"
        case .editPlanned(let p): return "plan-\(p.id)"
        case .newPlanned(let d): return "new-\(d.timeIntervalSince1970)"
        }
    }
}

struct WorkoutSheetView: View {
    let sheet: WorkoutSheet
    let profile: AthleteProfile

    var body: some View {
        switch sheet {
        case .log(let p, let d, let m):
            LogWorkoutSheet(planned: p, existing: nil, discipline: d ?? p?.discipline ?? .run, minutes: m ?? p?.minutes ?? 45)
        case .edit(let w):
            LogWorkoutSheet(planned: nil, existing: w, discipline: w.discipline, minutes: Int(w.durationMinutes.rounded()))
        case .move(let p, let suggested):
            RescheduleSheet(workout: p, profile: profile, suggested: suggested)
        case .editPlanned(let p):
            EditPlannedSheet(workout: p, date: p.date)
        case .newPlanned(let date):
            EditPlannedSheet(workout: nil, date: date)
        }
    }
}
