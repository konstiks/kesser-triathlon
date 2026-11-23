import SwiftData
import SwiftUI

/// Geplante Einheit bearbeiten oder neu anlegen.
struct EditPlannedSheet: View {
    let workout: PlannedWorkout?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var discipline: Discipline
    @State private var intensity: Intensity
    @State private var minutes: Int
    @State private var title: String
    @State private var details: String
    @State private var isKey: Bool

    init(workout: PlannedWorkout?, date: Date) {
        self.workout = workout
        _date = State(initialValue: workout?.date ?? date)
        _discipline = State(initialValue: workout?.discipline ?? .run)
        _intensity = State(initialValue: workout?.intensity ?? .easy)
        _minutes = State(initialValue: workout?.minutes ?? 45)
        _title = State(initialValue: workout?.title ?? "")
        _details = State(initialValue: workout?.details ?? "")
        _isKey = State(initialValue: workout?.isKey ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Tag", selection: $date, displayedComponents: .date)
                    Picker("Disziplin", selection: $discipline) {
                        ForEach(Discipline.allCases) { Label($0.name, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("Intensität", selection: $intensity) {
                        ForEach(Intensity.allCases) { Text($0.name).tag($0) }
                    }
                    Stepper("Dauer: \(formatMinutes(minutes))", value: $minutes, in: 10...480, step: 5)
                    Toggle("Schlüsseleinheit", isOn: $isKey)
                }
                Section("Beschreibung") {
                    TextField("Titel", text: $title)
                    TextField("Ablauf", text: $details, axis: .vertical).lineLimit(3...8)
                }
                if let workout {
                    Section {
                        Button("Einheit löschen", role: .destructive) {
                            context.delete(workout)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(workout == nil ? "Neue Einheit" : "Einheit bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { save() } }
            }
        }
    }

    private func save() {
        let finalTitle = title.isEmpty ? "\(discipline.name) \(intensity.shortName.lowercased())" : title
        let km = PlanGenerator.estimatedDistance(discipline, minutes: minutes, intensity: intensity)
        if let workout {
            if !workout.date.isSameDay(as: date) && workout.originalDate == nil { workout.originalDate = workout.date }
            workout.date = date.startOfDay
            workout.discipline = discipline
            workout.intensity = intensity
            if workout.minutes != minutes || workout.distanceKm == 0 { workout.distanceKm = km }
            workout.minutes = minutes
            workout.title = finalTitle
            workout.details = details
            workout.isKey = isKey
            // Selbst bearbeitete Einheiten beim Neu-Generieren behalten
            workout.isGenerated = false
        } else {
            let w = PlannedWorkout(date: date, discipline: discipline, intensity: intensity, minutes: minutes,
                                   distanceKm: km, title: finalTitle, details: details,
                                   isKey: isKey, isGenerated: false)
            context.insert(w)
        }
        try? context.save()
        dismiss()
    }
}
