import SwiftData
import SwiftUI

/// Einheit verschieben – mit Vorschlägen für Tage, an denen laut Kalender Zeit ist.
struct RescheduleSheet: View {
    let workout: PlannedWorkout
    let profile: AthleteProfile
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var calendar: CalendarManager
    @Query(sort: \PlannedWorkout.date) private var planned: [PlannedWorkout]
    @State private var date: Date

    init(workout: PlannedWorkout, profile: AthleteProfile, suggested: Date?) {
        self.workout = workout
        self.profile = profile
        _date = State(initialValue: suggested ?? max(workout.date, Date.now.startOfDay).adding(days: 1))
    }

    struct DayOption: Identifiable {
        let date: Date
        let free: Int
        let load: Int
        let fromCalendar: Bool
        var id: Date { date }
    }

    private var options: [DayOption] {
        (0...7).compactMap { offset -> DayOption? in
            let d = Date.now.startOfDay.adding(days: offset)
            guard d < profile.raceDay, !d.isSameDay(as: workout.date) else { return nil }
            let a = calendar.availability(on: d, profile: profile)
            let load = planned.filter { $0.date.isSameDay(as: d) && $0.status == .planned && $0.id != workout.id }
                .reduce(0) { $0 + $1.minutes }
            return DayOption(date: d, free: a.largestBlockMinutes, load: load, fromCalendar: a.fromCalendar)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { PlannedWorkoutRow(workout: workout) }
                Section {
                    ForEach(options) { o in
                        Button {
                            date = o.date
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(o.date.isToday ? "Heute" : o.date.shortDayText).foregroundStyle(.primary)
                                    Text(detail(o)).font(.caption).foregroundStyle(fits(o) ? Color.green : Color.secondary)
                                }
                                Spacer()
                                if date.isSameDay(as: o.date) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Wann passt es?")
                } footer: {
                    Text(calendar.hasAccess && profile.useCalendar
                         ? "Freie Zeit aus deinem Kalender, abzüglich bereits geplanter Einheiten."
                         : "Verbinde in den Einstellungen deinen Kalender, dann sehe ich deine Termine.")
                }
                Section {
                    DatePicker("Anderes Datum", selection: $date, in: Date.now.startOfDay...profile.raceDay, displayedComponents: .date)
                }
            }
            .navigationTitle("Verschieben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verschieben") {
                        if workout.originalDate == nil { workout.originalDate = workout.date }
                        workout.date = date.startOfDay
                        workout.status = .planned
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func fits(_ o: DayOption) -> Bool {
        o.free - o.load - 10 >= workout.minutes
    }

    private func detail(_ o: DayOption) -> String {
        var text = o.fromCalendar ? "\(formatMinutes(o.free)) am Stück frei" : "Budget \(formatMinutes(o.free))"
        if o.free == 0 && !o.fromCalendar { text = "Ruhetag" }
        if o.load > 0 { text += " · schon \(formatMinutes(o.load)) geplant" }
        return text
    }
}
