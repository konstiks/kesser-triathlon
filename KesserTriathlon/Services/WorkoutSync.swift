import Foundation
import SwiftData

/// Übernimmt Watch-Workouts aus Apple Health in die App und hakt passende Planeinheiten ab.
@MainActor
enum WorkoutSync {

    /// Gibt die Zahl neu importierter Trainings zurück.
    @discardableResult
    static func importFromHealth(context: ModelContext, profile: AthleteProfile, health: HealthKitManager) async -> Int {
        guard health.isAvailable, profile.healthConnected, !health.isSyncing else { return 0 }
        health.isSyncing = true
        health.lastError = nil
        defer { health.isSyncing = false }

        do {
            let sessions = try await health.fetchSessions(since: profile.healthImportStart.startOfDay)
            let existing = (try? context.fetch(FetchDescriptor<CompletedWorkout>())) ?? []
            let knownIDs = Set(existing.compactMap(\.healthKitID)).union(profile.ignoredHealthIDs)
            let planned = (try? context.fetch(FetchDescriptor<PlannedWorkout>())) ?? []

            var count = 0
            for s in sessions where !knownIDs.contains(s.id) {
                // Sehr kurze Aufzeichnungen (z. B. versehentlich gestartet) ignorieren
                guard s.minutes >= 5 else { continue }
                let w = CompletedWorkout(date: s.start, discipline: s.discipline,
                                         durationMinutes: s.minutes, distanceKm: s.km, source: .health)
                w.healthKitID = s.id
                w.avgHeartRate = s.avgHeartRate
                w.calories = s.calories
                context.insert(w)
                link(w, planned: planned)
                count += 1
            }
            profile.lastHealthSync = .now
            try? context.save()
            health.lastImportCount = count
            return count
        } catch {
            health.lastError = error.localizedDescription
            return 0
        }
    }

    /// Verknüpft ein absolviertes Training mit der passenden offenen Planeinheit desselben Tages
    /// (bei Bedarf auch mit einer verpassten aus den letzten 2 Tagen).
    static func link(_ workout: CompletedWorkout, planned: [PlannedWorkout]) {
        guard workout.plannedID == nil else { return }
        let open = planned.filter { $0.status == .planned && $0.discipline == workout.discipline }
        let sameDay = open.filter { $0.date.isSameDay(as: workout.date) }
            .min { abs(Double($0.minutes) - workout.durationMinutes) < abs(Double($1.minutes) - workout.durationMinutes) }
        let recentMissed = open.filter { $0.date < workout.date.startOfDay && $0.date >= workout.date.startOfDay.adding(days: -2) }
            .max { $0.date < $1.date }
        guard let match = sameDay ?? recentMissed else { return }
        markDone(match, with: workout)
    }

    static func markDone(_ planned: PlannedWorkout, with workout: CompletedWorkout) {
        planned.status = .done
        planned.completedID = workout.id
        workout.plannedID = planned.id
        workout.plannedIntensityRaw = planned.intensityRaw
    }

    /// Löst die Verknüpfung, wenn ein Training gelöscht wird.
    static func unlink(_ workout: CompletedWorkout, planned: [PlannedWorkout]) {
        guard let pid = workout.plannedID, let p = planned.first(where: { $0.id == pid }) else { return }
        p.status = .planned
        p.completedID = nil
    }
}
