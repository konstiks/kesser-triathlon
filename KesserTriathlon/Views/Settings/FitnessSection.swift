import SwiftData
import SwiftUI

/// Niveau und bisheriger Trainingsumfang je Disziplin.
struct FitnessSection: View {
    @Bindable var profile: AthleteProfile
    var onChange: () -> Void

    var body: some View {
        Section {
            ForEach(Experience.allCases) { level in
                Button {
                    profile.experience = level
                    onChange()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: level.symbol)
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.name).font(.headline).foregroundStyle(.primary)
                            Text(level.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: profile.experience == level ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(profile.experience == level ? Color.accentColor : Color.secondary)
                            .font(.title3)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Dein Niveau")
        } footer: {
            Text("Bestimmt Zielumfang, Intensität und Tempo. Einsteiger: ca. 4 h pro Woche zum Höhepunkt, Fortgeschrittene ca. 6 h, Profis ca. 9 h (für deine Distanz).")
        }

        Section {
            ForEach(Discipline.allCases) { d in
                Stepper(value: binding(for: d), in: 0...900, step: 15) {
                    HStack {
                        Image(systemName: d.symbol).foregroundStyle(d.color).frame(width: 24)
                        Text(d.name)
                        Spacer()
                        Text(profile.currentMinutes(for: d) == 0 ? "gar nicht" : formatMinutes(profile.currentMinutes(for: d)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("So viel trainierst du bisher pro Woche")
        } footer: {
            Text(focusText)
        }
    }

    private var focusText: String {
        if profile.currentWeeklyMinutes == 0 {
            return "Grobe Schätzung reicht. Der Plan startet bei deinem bisherigen Umfang und steigert ihn um höchstens ca. 10 % pro Woche."
        }
        if let focus = PlanGenerator.focusDiscipline(profile: profile) {
            return "Schwerpunkt im Plan: \(focus.name). Da trainierst du bisher am wenigsten, deshalb gibt es dafür mehr Einheiten."
        }
        return "Deine Disziplinen sind ausgeglichen. Der Plan verteilt die Einheiten gleichmäßig."
    }

    private func binding(for d: Discipline) -> Binding<Int> {
        Binding(
            get: { profile.currentMinutes(for: d) },
            set: { value in
                switch d {
                case .swim: profile.currentSwimMinutes = value
                case .bike: profile.currentBikeMinutes = value
                case .run: profile.currentRunMinutes = value
                }
                onChange()
            }
        )
    }
}

/// Wird Nutzern älterer Versionen einmal gezeigt, damit der Plan zum Niveau passt.
struct FitnessCheckSheet: View {
    @Bindable var profile: AthleteProfile
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Damit der Plan zu dir passt: Wie fit bist du gerade, und wie viel trainierst du schon? Der Plan startet dann sanft und steigert sich langsam.")
                        .font(.subheadline)
                }
                FitnessSection(profile: profile, onChange: {})
                Section {
                    Stepper(value: $profile.trainingDaysPerWeek, in: 1...7) {
                        HStack {
                            Text("Höchstens Trainingstage pro Woche")
                            Spacer()
                            Text("\(profile.trainingDaysPerWeek)").font(.headline.monospacedDigit())
                        }
                    }
                } footer: {
                    Text("Am Anfang plane ich oft weniger Tage. Mehr wird es erst, wenn der Umfang steigt.")
                }
            }
            .navigationTitle("Plan anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Plan erstellen") {
                        profile.fitnessSetupDone = true
                        PlanGenerator.regenerate(context: context, profile: profile)
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}
