import SwiftData
import SwiftUI

struct SettingsView: View {
    @Bindable var profile: AthleteProfile
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var calendar: CalendarManager
    @State private var confirmRegenerate = false
    @State private var planDirty = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                RaceSettingsSection(profile: profile, onChange: { planDirty = true })

                AvailabilitySection(profile: profile, onChange: { planDirty = true })

                Section {
                    if health.isAvailable {
                        if profile.healthConnected {
                            Label("Verbunden", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Button {
                                Task {
                                    let n = await WorkoutSync.importFromHealth(context: context, profile: profile, health: health)
                                    message = n == 0 ? "Keine neuen Trainings gefunden." : "\(n) Trainings übernommen. 🎉"
                                }
                            } label: {
                                HStack {
                                    Text("Jetzt abgleichen")
                                    Spacer()
                                    if health.isSyncing { ProgressView() }
                                }
                            }
                            DatePicker("Trainings übernehmen ab", selection: $profile.healthImportStart, displayedComponents: .date)
                            if let last = profile.lastHealthSync {
                                LabeledContent("Zuletzt", value: last.formatted(date: .abbreviated, time: .shortened))
                            }
                        } else {
                            Button {
                                Task {
                                    do {
                                        try await health.requestAuthorization()
                                        profile.healthConnected = true
                                        try? context.save()
                                        let n = await WorkoutSync.importFromHealth(context: context, profile: profile, health: health)
                                        message = "Apple Health verbunden. \(n) Trainings übernommen."
                                    } catch {
                                        message = error.localizedDescription
                                    }
                                }
                            } label: {
                                Label("Apple Health verbinden", systemImage: "heart.fill")
                            }
                        }
                        if let error = health.lastError {
                            Text(error).font(.caption).foregroundStyle(.orange)
                        }
                    } else {
                        Text("Apple Health ist auf diesem Gerät nicht verfügbar.")
                    }
                } header: {
                    Text("Apple Health & Apple Watch")
                } footer: {
                    Text("Schwimm-, Rad- und Lauftrainings der Watch (auch der Triathlon-Modus) werden automatisch übernommen und mit dem Plan abgeglichen. Danach nur noch die Ampel setzen. Falls nichts ankommt: Einstellungen › Health › Datenzugriff › Kesser Tri › alles erlauben.")
                }

                Section {
                    if calendar.hasAccess {
                        Toggle("Termine für Vorschläge nutzen", isOn: $profile.useCalendar)
                    } else {
                        Button {
                            Task {
                                if await calendar.requestAccess() {
                                    profile.useCalendar = true
                                    try? context.save()
                                } else {
                                    message = "Kein Kalenderzugriff. Du kannst ihn in den iOS-Einstellungen › Datenschutz › Kalender erlauben."
                                }
                            }
                        } label: {
                            Label("Kalender verbinden", systemImage: "calendar.badge.plus")
                        }
                    }
                    Stepper("Training ab \(profile.dayStartHour):00 Uhr", value: $profile.dayStartHour, in: 4...12)
                    Stepper("Training bis \(profile.dayEndHour):00 Uhr", value: $profile.dayEndHour, in: 16...23)
                } header: {
                    Text("Kalender")
                } footer: {
                    Text("Aus deinen Terminen (z. B. Arbeitstermine) berechne ich, wie viel Zeit am Stück frei ist, und passe Vorschläge an oder schlage einen besseren Tag vor. Termine verlassen nie dein iPhone.")
                }

                Section {
                    Button {
                        confirmRegenerate = true
                    } label: {
                        Label(planDirty ? "Plan mit neuen Einstellungen neu erstellen" : "Plan neu erstellen",
                              systemImage: "wand.and.stars")
                    }
                    if let at = profile.planGeneratedAt {
                        LabeledContent("Erstellt", value: at.formatted(date: .abbreviated, time: .omitted))
                    }
                } header: {
                    Text("Trainingsplan")
                } footer: {
                    Text("Erledigte Einheiten und selbst angelegte oder bearbeitete Einheiten bleiben erhalten.")
                }

                Section("Über") {
                    TextField("Dein Name", text: $profile.name)
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
            .navigationTitle("Einstellungen")
            .onChange(of: profile.useCalendar) { _, _ in try? context.save() }
            .confirmationDialog("Plan ab heute neu erstellen?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
                Button("Neu erstellen") {
                    PlanGenerator.regenerate(context: context, profile: profile)
                    planDirty = false
                    message = "Neuer Plan steht. Viel Spaß! 💪"
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

struct RaceSettingsSection: View {
    @Bindable var profile: AthleteProfile
    var onChange: () -> Void

    var body: some View {
        Section("Wettkampf") {
            TextField("Name", text: $profile.raceName)
            DatePicker("Datum", selection: $profile.raceDate, in: Date.now..., displayedComponents: .date)
                .onChange(of: profile.raceDate) { _, _ in onChange() }
            Picker("Distanz", selection: Binding(get: { profile.raceType }, set: { profile.raceType = $0; onChange() })) {
                ForEach(RaceType.allCases) { Text($0.name).tag($0) }
            }
            distanceRow(.swim, value: $profile.swimKm, step: 0.05)
            distanceRow(.bike, value: $profile.bikeKm, step: 1)
            distanceRow(.run, value: $profile.runKm, step: 0.5)
        }
    }

    private func distanceRow(_ d: Discipline, value: Binding<Double>, step: Double) -> some View {
        Stepper(value: Binding(get: { value.wrappedValue }, set: {
            value.wrappedValue = max(step, $0)
            profile.raceTypeRaw = RaceType.custom.rawValue
            onChange()
        }), step: step) {
            HStack {
                Image(systemName: d.symbol).foregroundStyle(d.color).frame(width: 24)
                Text(d.name)
                Spacer()
                Text(d.formatDistance(value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}

struct AvailabilitySection: View {
    @Bindable var profile: AthleteProfile
    var onChange: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ruhetage")
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { i in
                        let isRest = profile.restDays.contains(i)
                        Button {
                            if isRest { profile.restDays.removeAll { $0 == i } } else { profile.restDays.append(i) }
                            onChange()
                        } label: {
                            Text(Weekdays.short[i])
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(isRest ? Color.accentColor : Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(isRest ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Stepper("Werktags max. \(formatMinutes(profile.weekdayMaxMinutes))",
                    value: Binding(get: { profile.weekdayMaxMinutes }, set: { profile.weekdayMaxMinutes = $0; onChange() }),
                    in: 20...240, step: 15)
            Stepper("Wochenende max. \(formatMinutes(profile.weekendMaxMinutes))",
                    value: Binding(get: { profile.weekendMaxMinutes }, set: { profile.weekendMaxMinutes = $0; onChange() }),
                    in: 30...480, step: 15)
        } header: {
            Text("Verfügbarkeit")
        } footer: {
            Text("Der Plan hält sich an diese Grenzen. Lange Einheiten landen am Wochenende.")
        }
    }
}
