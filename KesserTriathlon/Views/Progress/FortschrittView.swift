import Charts
import SwiftData
import SwiftUI

struct FortschrittView: View {
    let profile: AthleteProfile
    @Query(sort: \PlannedWorkout.date) private var planned: [PlannedWorkout]
    @Query(sort: \CompletedWorkout.date, order: .reverse) private var completed: [CompletedWorkout]
    @State private var sheet: WorkoutSheet?

    var body: some View {
        let progress = ProgressEngine.allProgress(completed: completed, planned: planned, profile: profile)
        let level = ProgressEngine.level(completed: completed, planned: planned)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    overall(level: level, progress: progress)
                    ForEach(progress) { p in DisciplineCard(progress: p) }
                    weeklyChart
                    planAdherence
                    history
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Fortschritt")
            .sheet(item: $sheet) { s in WorkoutSheetView(sheet: s, profile: profile) }
        }
    }

    private func overall(level: LevelInfo, progress: [DisciplineProgress]) -> some View {
        let readiness = progress.map(\.readiness).reduce(0, +) / Double(max(1, progress.count))
        return HStack(spacing: 16) {
            KonstiView(discipline: progress.max(by: { $0.readiness < $1.readiness })?.discipline ?? .run,
                       level: level, action: true, size: 110)
            VStack(alignment: .leading, spacing: 6) {
                Text("Wettkampf-Form").font(.caption).foregroundStyle(.secondary)
                Text("\(Int(readiness * 100)) %").font(.system(size: 40, weight: .heavy, design: .monospaced))
                Label("\(level.tier.name) · Level \(level.level)", systemImage: level.tier.symbol)
                    .font(.subheadline.weight(.semibold))
                Text("\(completed.count) Trainings · \(formatMinutes(Int(completed.reduce(0) { $0 + $1.durationMinutes }))) gesamt")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private struct WeekBar: Identifiable {
        let id = UUID()
        let week: Date
        let discipline: Discipline
        let minutes: Double
    }

    private var weeklyChart: some View {
        let thisWeek = Date.now.startOfWeek
        var bars: [WeekBar] = []
        for i in (0..<8).reversed() {
            let start = thisWeek.adding(days: -7 * i)
            let end = start.adding(days: 7)
            for d in Discipline.allCases {
                let m = completed.filter { $0.discipline == d && $0.date >= start && $0.date < end }
                    .reduce(0) { $0 + $1.durationMinutes }
                bars.append(WeekBar(week: start, discipline: d, minutes: m))
            }
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Trainingszeit pro Woche").font(.headline)
            Chart(bars) { bar in
                BarMark(
                    x: .value("Woche", bar.week, unit: .weekOfYear),
                    y: .value("Stunden", bar.minutes / 60)
                )
                .foregroundStyle(by: .value("Disziplin", bar.discipline.name))
            }
            .chartForegroundStyleScale([
                Discipline.swim.name: Discipline.swim.color,
                Discipline.bike.name: Discipline.bike.color,
                Discipline.run.name: Discipline.run.color,
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel { Text("KW\(date.weekOfYear)") }
                    }
                }
            }
            .chartYAxisLabel("Stunden")
            .frame(height: 200)
        }
        .card()
    }

    private var planAdherence: some View {
        let past = planned.filter { $0.date < Date.now.startOfDay.adding(days: 1) }
        let done = past.filter { $0.status == .done }.count
        let skipped = past.filter { $0.status == .skipped }.count
        let open = past.count - done - skipped
        let ratio = past.isEmpty ? 0 : Double(done) / Double(past.count)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Plantreue").font(.headline)
                Spacer()
                Text("\(Int(ratio * 100)) %").font(.headline.monospacedDigit())
            }
            PixelBar(value: ratio, color: .accentColor)
            HStack(spacing: 14) {
                Label("\(done) erledigt", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Label("\(open) offen", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                Label("\(skipped) ausgelassen", systemImage: "xmark.circle").foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .card()
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Verlauf", trailing: "\(completed.count)")
            if completed.isEmpty {
                Text("Noch keine Trainings. Trag eins ein oder verbinde Apple Health.")
                    .font(.subheadline).foregroundStyle(.secondary).card()
            } else {
                VStack(spacing: 12) {
                    ForEach(completed.prefix(50)) { w in
                        Button { sheet = .edit(w) } label: { CompletedWorkoutRow(workout: w) }
                            .buttonStyle(.plain)
                        if w.id != completed.prefix(50).last?.id { Divider() }
                    }
                }
                .card()
            }
        }
    }
}

struct DisciplineCard: View {
    let progress: DisciplineProgress

    var body: some View {
        let d = progress.discipline
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DisciplineIcon(discipline: d)
                VStack(alignment: .leading, spacing: 1) {
                    Text(d.name).font(.headline)
                    Label(progress.tier.name, systemImage: progress.tier.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(progress.tier == .frischling ? Color.secondary : progress.tier.color)
                }
                Spacer()
                Text("\(Int(progress.readiness * 100)) %")
                    .font(.title3.weight(.bold).monospacedDigit())
            }
            PixelBar(value: progress.readiness, color: d.color)
            HStack {
                stat("Längste (6 Wo.)", "\(d.formatDistance(progress.longestKm)) / \(d.formatDistance(progress.targetKm))")
                Spacer()
                stat("Plan 4 Wo.", "\(Int(progress.consistency * 100)) %")
                Spacer()
                stat("Gesamt", d.formatDistance(progress.totalKm))
            }
        }
        .card()
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold).monospacedDigit())
        }
    }
}
