import SwiftUI

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

/// Pixeliger Fortschrittsbalken (passend zu Pixel-Konsti).
struct PixelBar: View {
    let value: Double
    let color: Color
    var height: CGFloat = 14
    var segments: Int = 20

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let w = (geo.size.width - gap * CGFloat(segments - 1)) / CGFloat(segments)
            let filled = Int((min(1, max(0, value)) * Double(segments)).rounded())
            HStack(spacing: gap) {
                ForEach(0..<segments, id: \.self) { i in
                    Rectangle()
                        .fill(i < filled ? color : color.opacity(0.15))
                        .frame(width: max(1, w))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100)) Prozent")
    }
}

struct DisciplineIcon: View {
    let discipline: Discipline
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: discipline.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(discipline.color, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct IntensityTag: View {
    let intensity: Intensity

    var body: some View {
        Text(intensity.shortName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(intensity.color.opacity(0.18), in: Capsule())
            .foregroundStyle(intensity.color)
    }
}

/// Ampel-Auswahl (Grün / Gelb / Rot).
struct AmpelPicker: View {
    let title: String
    @Binding var selection: Ampel?
    let label: (Ampel) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                ForEach(Ampel.allCases) { a in
                    Button {
                        selection = (selection == a) ? nil : a
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(a.color.opacity(selection == a ? 1 : 0.25))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(a.color, lineWidth: selection == a ? 3 : 1))
                            Text(label(a))
                                .font(.caption2)
                                .foregroundStyle(selection == a ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Kleine Ampel-Anzeige.
struct AmpelDots: View {
    let mood: Ampel?
    let effort: Ampel?

    var body: some View {
        HStack(spacing: 4) {
            dot(mood).accessibilityLabel("Stimmung")
            dot(effort).accessibilityLabel("Schwere")
        }
    }

    @ViewBuilder private func dot(_ a: Ampel?) -> some View {
        Circle()
            .fill(a?.color ?? Color.gray.opacity(0.3))
            .frame(width: 10, height: 10)
    }
}

struct PlannedWorkoutRow: View {
    let workout: PlannedWorkout

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DisciplineIcon(discipline: workout.discipline)
                .opacity(workout.status == .skipped ? 0.4 : 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(workout.title)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(workout.status == .skipped)
                    if workout.isKey {
                        ImportantTag()
                    }
                }
                HStack(spacing: 6) {
                    Text(formatMinutes(workout.minutes))
                    if workout.distanceKm > 0 {
                        Text("· ca. \(workout.discipline.formatDistance(workout.distanceKm))")
                    }
                    IntensityTag(intensity: workout.intensity)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if workout.wasMoved, let original = workout.originalDate {
                    Text("verschoben vom \(original.shortDayText)")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            statusIcon
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch workout.status {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
        case .skipped:
            Image(systemName: "xmark.circle").foregroundStyle(.secondary).font(.title3)
        case .planned:
            if workout.isOverdue {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).font(.title3)
            } else {
                Image(systemName: "circle").foregroundStyle(.tertiary).font(.title3)
            }
        }
    }
}

struct CompletedWorkoutRow: View {
    let workout: CompletedWorkout

    var body: some View {
        HStack(spacing: 12) {
            DisciplineIcon(discipline: workout.discipline, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(workout.discipline.name).font(.subheadline.weight(.semibold))
                    if workout.source == .health {
                        Image(systemName: "applewatch").font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("Von der Apple Watch")
                    }
                }
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if workout.isRated {
                AmpelDots(mood: workout.mood, effort: workout.effort)
            } else {
                Text("Bewerten").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
            }
        }
    }

    private var summary: String {
        var parts = [workout.date.shortDayText, formatMinutes(Int(workout.durationMinutes.rounded()))]
        if workout.distanceKm > 0 { parts.append(workout.discipline.formatDistance(workout.distanceKm)) }
        if let pace = workout.paceText { parts.append(pace) }
        return parts.joined(separator: " · ")
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.top, 8)
    }
}

/// Markiert die wichtigsten Einheiten der Woche (lange Einheiten, Intervalle).
struct ImportantTag: View {
    var body: some View {
        Label("Wichtig", systemImage: "star.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.yellow.opacity(0.22), in: Capsule())
            .foregroundStyle(Color.orange)
            .accessibilityLabel("Wichtige Einheit")
    }
}
