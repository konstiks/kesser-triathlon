import SwiftUI

struct CountdownCard: View {
    let profile: AthleteProfile

    var body: some View {
        let days = profile.daysUntilRace
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.raceName)
                    .font(.headline)
                Text("\(profile.raceDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "de_DE"))))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(profile.raceType == .custom
                     ? "\(Discipline.swim.formatDistance(profile.swimKm)) · \(Discipline.bike.formatDistance(profile.bikeKm)) · \(Discipline.run.formatDistance(profile.runKm))"
                     : "\(profile.raceType.name): \(Discipline.swim.formatDistance(profile.swimKm)) · \(Discipline.bike.formatDistance(profile.bikeKm)) · \(Discipline.run.formatDistance(profile.runKm))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                let phase = PlanGenerator.phase(on: .now, profile: profile)
                Text(phase.name)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
            }
            Spacer()
            VStack(spacing: 0) {
                if days > 0 {
                    Text("\(days)")
                        .font(.system(size: 44, weight: .heavy, design: .monospaced))
                        .contentTransition(.numericText())
                    Text(days == 1 ? "Tag" : "Tage").font(.caption.weight(.semibold))
                } else if days == 0 {
                    Text("🏁").font(.system(size: 44))
                    Text("Heute!").font(.caption.weight(.semibold))
                } else {
                    Text("🏅").font(.system(size: 44))
                    Text("Geschafft").font(.caption.weight(.semibold))
                }
            }
            .frame(minWidth: 90)
        }
        .card()
    }
}
