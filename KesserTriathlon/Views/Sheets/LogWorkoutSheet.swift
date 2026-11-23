import SwiftData
import SwiftUI

/// Training eintragen oder bearbeiten (inkl. Ampel für Stimmung und Schwere).
struct LogWorkoutSheet: View {
    let planned: PlannedWorkout?
    let existing: CompletedWorkout?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allPlanned: [PlannedWorkout]
    @Query private var profiles: [AthleteProfile]

    @State private var discipline: Discipline
    @State private var date: Date
    @State private var hours: Int
    @State private var mins: Int
    @State private var distanceText: String
    @State private var mood: Ampel?
    @State private var effort: Ampel?
    @State private var notes: String
    @State private var confirmDelete = false

    init(planned: PlannedWorkout?, existing: CompletedWorkout?, discipline: Discipline, minutes: Int) {
        self.planned = planned
        self.existing = existing
        let total = existing.map { Int($0.durationMinutes.rounded()) } ?? minutes
        _discipline = State(initialValue: existing?.discipline ?? discipline)
        var start = existing?.date ?? .now
        if existing == nil, let p = planned, !p.date.isToday {
            start = Calendar.de.date(bySettingHour: 18, minute: 0, second: 0, of: p.date) ?? p.date
        }
        _date = State(initialValue: start)
        _hours = State(initialValue: total / 60)
        _mins = State(initialValue: total % 60)
        let km = existing?.distanceKm ?? planned?.distanceKm ?? 0
        let d = existing?.discipline ?? discipline
        _distanceText = State(initialValue: km > 0 ? LogWorkoutSheet.format(km: km, for: d) : "")
        _mood = State(initialValue: existing?.mood)
        _effort = State(initialValue: existing?.effort)
        _notes = State(initialValue: existing?.notes ?? "")
    }

    private var isHealthImport: Bool { existing?.source == .health }

    var body: some View {
        NavigationStack {
            Form {
                if let planned {
                    Section {
                        PlannedWorkoutRow(workout: planned)
                    } header: { Text("Geplante Einheit") }
                }
                Section {
                    Picker("Disziplin", selection: $discipline) {
                        ForEach(Discipline.allCases) { d in
                            Label(d.name, systemImage: d.symbol).tag(d)
                        }
                    }
                    .disabled(isHealthImport)
                    DatePicker("Wann", selection: $date, in: ...Date.now.adding(days: 1))
                    HStack {
                        Text("Dauer")
                        Spacer()
                        Picker("Stunden", selection: $hours) {
                            ForEach(0..<13) { Text("\($0) h").tag($0) }
                        }
                        .pickerStyle(.menu)
                        Picker("Minuten", selection: $mins) {
                            ForEach(Array(stride(from: 0, to: 60, by: 1)), id: \.self) { Text("\($0) min").tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                    HStack {
                        Text("Distanz")
                        Spacer()
                        TextField(discipline == .swim ? "Meter" : "km", text: $distanceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                        Text(discipline == .swim ? "m" : "km").foregroundStyle(.secondary)
                    }
                    if let existing, existing.source == .health {
                        if let hr = existing.avgHeartRate {
                            LabeledContent("Ø Herzfrequenz", value: "\(Int(hr)) bpm")
                        }
                        if let kcal = existing.calories {
                            LabeledContent("Aktive Kalorien", value: "\(Int(kcal)) kcal")
                        }
                        Label("Von der Apple Watch übernommen", systemImage: "applewatch")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Training") }

                Section {
                    AmpelPicker(title: "Stimmung", selection: $mood, label: { $0.moodLabel })
                    AmpelPicker(title: "Gefühlte Schwere", selection: $effort, label: { $0.effortLabel })
                } header: { Text("Ampel") } footer: {
                    Text("Die Ampel steuert die Vorschläge: Nach roten Einheiten wird es automatisch ruhiger.")
                }

                Section("Notizen") {
                    TextField("Wie lief's? Wetter, Beine, Kopf …", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if existing != nil {
                    Section {
                        Button("Training löschen", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Training eintragen" : "Training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }.disabled(hours == 0 && mins == 0)
                }
            }
            .confirmationDialog("Training wirklich löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { delete() }
            } message: {
                if isHealthImport {
                    Text("In Apple Health bleibt es erhalten und wird nicht erneut importiert.")
                }
            }
        }
    }

    private var distanceKm: Double {
        let value = Double(distanceText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return discipline == .swim ? value / 1000 : value
    }

    static func format(km: Double, for d: Discipline) -> String {
        if d == .swim { return "\(Int((km * 1000).rounded()))" }
        return String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",")
    }

    private func save() {
        let minutes = Double(hours * 60 + mins)
        let workout: CompletedWorkout
        if let existing {
            workout = existing
            workout.discipline = discipline
            workout.date = date
            workout.durationMinutes = minutes
            workout.distanceKm = distanceKm
        } else {
            workout = CompletedWorkout(date: date, discipline: discipline, durationMinutes: minutes, distanceKm: distanceKm)
            context.insert(workout)
        }
        workout.mood = mood
        workout.effort = effort
        workout.notes = notes

        if let planned, planned.status == .planned {
            WorkoutSync.markDone(planned, with: workout)
        } else if existing == nil {
            WorkoutSync.link(workout, planned: allPlanned)
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        guard let existing else { return }
        WorkoutSync.unlink(existing, planned: allPlanned)
        if let hkID = existing.healthKitID, let profile = profiles.first, !profile.ignoredHealthIDs.contains(hkID) {
            // merken, damit der Import es nicht erneut anlegt
            profile.ignoredHealthIDs.append(hkID)
        }
        context.delete(existing)
        try? context.save()
        dismiss()
    }
}
