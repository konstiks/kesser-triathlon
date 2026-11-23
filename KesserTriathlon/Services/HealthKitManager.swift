import Foundation
import HealthKit

/// Ein Training aus Apple Health, bereits auf eine Disziplin abgebildet.
struct HealthSession {
    let id: String
    let discipline: Discipline
    let start: Date
    let minutes: Double
    let km: Double
    let avgHeartRate: Double?
    let calories: Double?
}

/// Liest Workouts der Apple Watch (Apple Health / Fitness) aus.
@MainActor
final class HealthKitManager: ObservableObject {
    private let store = HKHealthStore()

    @Published var isSyncing = false
    @Published var lastError: String?
    @Published var lastImportCount: Int?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceSwimming),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
        ]
    }

    /// Zeigt den Health-Berechtigungsdialog (nur Lesen).
    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthError.notAvailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    enum HealthError: LocalizedError {
        case notAvailable
        var errorDescription: String? { "Apple Health ist auf diesem Gerät nicht verfügbar." }
    }

    /// Alle Schwimm-, Rad- und Lauf-Workouts seit `start`.
    /// Multisport-Workouts (Triathlon-Modus der Watch) werden in ihre Einzeldisziplinen zerlegt.
    func fetchSessions(since start: Date) async throws -> [HealthSession] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: nil
        )
        let workouts = try await descriptor.result(for: store)
        return workouts.flatMap(sessions(from:))
    }

    private func sessions(from workout: HKWorkout) -> [HealthSession] {
        if workout.workoutActivityType == .swimBikeRun {
            return workout.workoutActivities.compactMap { activity -> HealthSession? in
                guard let d = Self.discipline(for: activity.workoutConfiguration.activityType) else { return nil }
                return HealthSession(
                    id: activity.uuid.uuidString,
                    discipline: d,
                    start: activity.startDate,
                    minutes: activity.duration / 60,
                    km: Self.km(activity.statistics(for: Self.distanceType(for: d))),
                    avgHeartRate: Self.bpm(activity.statistics(for: HKQuantityType(.heartRate))),
                    calories: Self.kcal(activity.statistics(for: HKQuantityType(.activeEnergyBurned)))
                )
            }
        }
        guard let d = Self.discipline(for: workout.workoutActivityType) else { return [] }
        return [HealthSession(
            id: workout.uuid.uuidString,
            discipline: d,
            start: workout.startDate,
            minutes: workout.duration / 60,
            km: Self.km(workout.statistics(for: Self.distanceType(for: d))),
            avgHeartRate: Self.bpm(workout.statistics(for: HKQuantityType(.heartRate))),
            calories: Self.kcal(workout.statistics(for: HKQuantityType(.activeEnergyBurned)))
        )]
    }

    private static func discipline(for type: HKWorkoutActivityType) -> Discipline? {
        switch type {
        case .swimming: return .swim
        case .cycling, .handCycling: return .bike
        case .running: return .run
        default: return nil
        }
    }

    private static func distanceType(for d: Discipline) -> HKQuantityType {
        switch d {
        case .swim: return HKQuantityType(.distanceSwimming)
        case .bike: return HKQuantityType(.distanceCycling)
        case .run: return HKQuantityType(.distanceWalkingRunning)
        }
    }

    private static func km(_ stats: HKStatistics?) -> Double {
        stats?.sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo)) ?? 0
    }

    private static func bpm(_ stats: HKStatistics?) -> Double? {
        stats?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }

    private static func kcal(_ stats: HKStatistics?) -> Double? {
        stats?.sumQuantity()?.doubleValue(for: .kilocalorie())
    }
}
