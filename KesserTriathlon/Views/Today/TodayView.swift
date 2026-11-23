import EventKit
import SwiftData
import SwiftUI

struct TodayView: View {
    let profile: AthleteProfile
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var calendar: CalendarManager
    @Query(sort: \PlannedWorkout.date) private var planned: [PlannedWorkout]
    @Query(sort: \CompletedWorkout.date, order: .reverse) private var completed: [CompletedWorkout]
    @State private var sheet: WorkoutSheet?

    var body: some View {
        let _ = calendar.revision
        let progress = ProgressEngine.allProgress(completed: completed, planned: planned, profile: profile)
        let level = ProgressEngine.level(completed: completed, planned: planned)
        let suggestion = SuggestionEngine.suggest(
            planned: planned, completed: completed, profile: profile, progress: progress,
            availability: { calendar.availability(on: $0, profile: profile) }
        )
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    CountdownCard(profile: profile)
                    KonstiCard(level: level,
                               discipline: suggestion.discipline ?? todayPlanned.first?.discipline ?? .run,
                               speech: suggestion.speech,
                               action: suggestion.kind == .done || suggestion.kind == .race)
                    SuggestionCard(
                        suggestion: suggestion,
                        onLog: {
                            let p = planned.first { $0.id == suggestion.plannedID }
                            sheet = .log(planned: p, discipline: suggestion.discipline, minutes: suggestion.minutes)
                        },
                        onMove: {
                            guard let p = planned.first(where: { $0.id == suggestion.plannedID }) else { return }
                            sheet = .move(p, suggested: suggestion.moveTo)
                        }
                    )
                    todaySection
                    unratedSection
                    overdueSection
                    eventsSection
                    healthStatus
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Hallo \(profile.name)!")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if profile.healthConnected {
                        Button {
                            Task { await sync() }
                        } label: {
                            if health.isSyncing { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath") }
                        }
                        .accessibilityLabel("Mit Apple Health abgleichen")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .log(planned: nil, discipline: nil, minutes: nil) } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Training eintragen")
                }
            }
            .refreshable { await sync() }
            .sheet(item: $sheet) { s in
                WorkoutSheetView(sheet: s, profile: profile)
            }
        }
    }

    private var todayPlanned: [PlannedWorkout] {
        planned.filter { $0.date.isToday }
    }

    private func sync() async {
        await WorkoutSync.importFromHealth(context: context, profile: profile, health: health)
    }

    @ViewBuilder private var todaySection: some View {
        if !todayPlanned.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Heute geplant", trailing: formatMinutes(todayPlanned.reduce(0) { $0 + $1.minutes }))
                ForEach(todayPlanned) { w in
                    PlannedWorkoutMenu(workout: w, sheet: $sheet) {
                        VStack(alignment: .leading, spacing: 8) {
                            PlannedWorkoutRow(workout: w)
                            if !w.details.isEmpty {
                                Text(w.details).font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            if w.isKey && w.status == .planned {
                                Text("★ Wichtige Einheit der Woche: möglichst nicht ausfallen lassen. Wenn's heute nicht passt, lieber verschieben.")
                                    .font(.caption2).foregroundStyle(.orange)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .card()
                    }
                }
            }
        }
    }

    @ViewBuilder private var unratedSection: some View {
        let unrated = completed.filter { !$0.isRated && $0.date >= Date.now.adding(days: -7) }
        if !unrated.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Wie war's?", trailing: "Ampel setzen")
                ForEach(unrated) { w in
                    Button { sheet = .edit(w) } label: {
                        CompletedWorkoutRow(workout: w).card()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var overdueSection: some View {
        let overdue = planned.filter { $0.isOverdue && $0.date >= Date.now.adding(days: -7).startOfDay }
        if !overdue.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Offen geblieben", trailing: "\(overdue.count)")
                ForEach(overdue) { w in
                    PlannedWorkoutMenu(workout: w, sheet: $sheet) {
                        PlannedWorkoutRow(workout: w).card()
                    }
                }
            }
        }
    }

    @ViewBuilder private var eventsSection: some View {
        if calendar.hasAccess && profile.useCalendar {
            let events = calendar.events(on: .now)
            let avail = calendar.availability(on: .now, profile: profile)
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Termine heute", trailing: "\(formatMinutes(avail.largestBlockMinutes)) am Stück frei")
                if events.isEmpty {
                    Text("Keine Termine. Freie Bahn! 🚀").font(.subheadline).foregroundStyle(.secondary).card()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(events, id: \.eventIdentifier) { e in
                            HStack {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(cgColor: e.calendar.cgColor))
                                    .frame(width: 4, height: 28)
                                VStack(alignment: .leading) {
                                    Text(e.title ?? "Termin").font(.subheadline)
                                    Text(e.isAllDay ? "ganztägig" : "\(e.startDate.timeText)–\(e.endDate.timeText)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .card()
                }
            }
        }
    }

    @ViewBuilder private var healthStatus: some View {
        if let error = health.lastError {
            Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        } else if let last = profile.lastHealthSync {
            Text("Apple Health zuletzt abgeglichen: \(last.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
        } else if !profile.healthConnected {
            Text("Tipp: Unter Einstellungen Apple Health verbinden, dann landen deine Watch-Trainings automatisch hier.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Tippen auf eine Planeinheit öffnet ein Menü mit den Aktionen.
struct PlannedWorkoutMenu<Content: View>: View {
    let workout: PlannedWorkout
    @Binding var sheet: WorkoutSheet?
    @ViewBuilder let label: () -> Content
    @Environment(\.modelContext) private var context

    var body: some View {
        Menu {
            if workout.status == .planned {
                Button {
                    sheet = .log(planned: workout, discipline: workout.discipline, minutes: workout.minutes)
                } label: { Label("Erledigt – eintragen", systemImage: "checkmark.circle") }
                if !workout.date.isToday {
                    Button {
                        move(to: .now)
                    } label: { Label("Auf heute legen", systemImage: "arrow.down.to.line") }
                }
                Button {
                    sheet = .move(workout, suggested: nil)
                } label: { Label("Verschieben …", systemImage: "calendar.badge.clock") }
                Button {
                    workout.status = .skipped
                    try? context.save()
                } label: { Label("Auslassen", systemImage: "xmark.circle") }
            } else {
                Button {
                    workout.status = .planned
                    workout.completedID = nil
                    try? context.save()
                } label: { Label("Wieder öffnen", systemImage: "arrow.uturn.backward") }
            }
            Button {
                sheet = .editPlanned(workout)
            } label: { Label("Bearbeiten", systemImage: "pencil") }
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }

    private func move(to date: Date) {
        if workout.originalDate == nil { workout.originalDate = workout.date }
        workout.date = date.startOfDay
        try? context.save()
    }
}
