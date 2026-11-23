import SwiftData
import SwiftUI

/// Wochenplan mit Tagesansicht.
struct PlanView: View {
    let profile: AthleteProfile
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var calendar: CalendarManager
    @Query(sort: \PlannedWorkout.date) private var planned: [PlannedWorkout]
    @Query(sort: \CompletedWorkout.date) private var completed: [CompletedWorkout]
    @State private var weekStart = Date.now.startOfWeek
    @State private var sheet: WorkoutSheet?

    private var days: [Date] { (0..<7).map { weekStart.adding(days: $0) } }
    private var weekPlanned: [PlannedWorkout] {
        planned.filter { $0.date >= weekStart && $0.date < weekStart.adding(days: 7) }
    }

    var body: some View {
        let _ = calendar.revision
        NavigationStack {
            List {
                Section { weekHeader }
                ForEach(days, id: \.self) { day in
                    daySection(day)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Trainingsplan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { sheet = .newPlanned(max(weekStart, Date.now.startOfDay)) } label: {
                            Label("Einheit hinzufügen", systemImage: "plus")
                        }
                        Button { weekStart = Date.now.startOfWeek } label: {
                            Label("Diese Woche", systemImage: "calendar.circle")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(item: $sheet) { s in WorkoutSheetView(sheet: s, profile: profile) }
        }
    }

    private var weekHeader: some View {
        let total = weekPlanned.reduce(0) { $0 + $1.minutes }
        let done = weekPlanned.filter { $0.status == .done }.count
        let phase = weekPlanned.first?.phase ?? PlanGenerator.phase(on: weekStart, profile: profile)
        let perDiscipline = Dictionary(grouping: weekPlanned, by: \.discipline).mapValues { $0.reduce(0) { $0 + $1.minutes } }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { withAnimation { weekStart = weekStart.adding(days: -7) } } label: {
                    Image(systemName: "chevron.left.circle.fill").font(.title2)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("KW \(weekStart.weekOfYear)").font(.headline)
                    Text("\(weekStart.shortDayText) – \(weekStart.adding(days: 6).shortDayText)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { withAnimation { weekStart = weekStart.adding(days: 7) } } label: {
                    Image(systemName: "chevron.right.circle.fill").font(.title2)
                }
            }
            .buttonStyle(.borderless)
            if !weekPlanned.isEmpty {
                Text(phase.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                Text(phase.explanation).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Label(formatMinutes(total), systemImage: "clock")
                    Label("\(done)/\(weekPlanned.count)", systemImage: "checkmark.circle")
                    Spacer()
                    ForEach(Discipline.allCases) { d in
                        if let m = perDiscipline[d] {
                            HStack(spacing: 3) {
                                Image(systemName: d.symbol).foregroundStyle(d.color)
                                Text(formatMinutes(m))
                            }
                        }
                    }
                }
                .font(.caption.weight(.medium))
            } else {
                Text(weekStart > profile.raceDay ? "Nach dem Wettkampf: genießen! 🍻" : "Für diese Woche ist nichts geplant.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func daySection(_ day: Date) -> some View {
        let items = weekPlanned.filter { $0.date.isSameDay(as: day) }
        let extra = completed.filter { $0.date.isSameDay(as: day) && $0.plannedID == nil }
        let isRace = day.isSameDay(as: profile.raceDay)
        Section {
            if isRace {
                Label("\(profile.raceName) – Wettkampftag!", systemImage: "flag.checkered")
                    .font(.headline)
            }
            ForEach(items) { w in
                PlannedWorkoutMenu(workout: w, sheet: $sheet) {
                    PlannedWorkoutRow(workout: w).contentShape(Rectangle())
                }
                .swipeActions(edge: .leading) {
                    if w.status == .planned {
                        Button { sheet = .log(planned: w, discipline: w.discipline, minutes: w.minutes) } label: {
                            Label("Erledigt", systemImage: "checkmark")
                        }
                        .tint(.green)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button { sheet = .move(w, suggested: nil) } label: {
                        Label("Verschieben", systemImage: "calendar.badge.clock")
                    }
                    .tint(.orange)
                }
            }
            ForEach(extra) { w in
                Button { sheet = .edit(w) } label: { CompletedWorkoutRow(workout: w) }
                    .buttonStyle(.plain)
            }
            if items.isEmpty && extra.isEmpty && !isRace {
                Text(profile.restDays.contains(day.weekdayIndex) ? "Fester Ruhetag 😴" : "Trainingsfrei 😴")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text(day.isToday ? "Heute · \(day.shortDayText)" : day.shortDayText)
                    .fontWeight(day.isToday ? .bold : .regular)
                Spacer()
                if calendar.hasAccess && profile.useCalendar && day >= Date.now.startOfDay {
                    let a = calendar.availability(on: day, profile: profile)
                    Text(a.eventCount > 0 ? "\(a.eventCount) Termine · \(formatMinutes(a.largestBlockMinutes)) frei" : "keine Termine")
                        .textCase(nil)
                }
            }
        }
    }
}
