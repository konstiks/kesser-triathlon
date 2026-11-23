import SwiftUI

struct SuggestionCard: View {
    let suggestion: Suggestion
    var onLog: () -> Void
    var onMove: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let d = suggestion.discipline, suggestion.kind == .train {
                    DisciplineIcon(discipline: d, size: 40)
                } else {
                    Image(systemName: icon)
                        .font(.title2)
                        .frame(width: 40, height: 40)
                        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vorschlag für heute").font(.caption).foregroundStyle(.secondary)
                    Text(suggestion.headline).font(.headline)
                }
            }
            if suggestion.kind == .train {
                HStack(spacing: 8) {
                    Label(formatMinutes(suggestion.minutes), systemImage: "clock")
                        .font(.subheadline.weight(.semibold))
                    IntensityTag(intensity: suggestion.intensity)
                }
            }
            ForEach(suggestion.reasons, id: \.self) { reason in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "sparkle").font(.caption2).foregroundStyle(Color.accentColor).padding(.top, 3)
                    Text(reason).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if suggestion.kind == .train || suggestion.moveTo != nil {
                HStack {
                    if suggestion.kind == .train {
                        Button(action: onLog) {
                            Label("Eintragen", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if let onMove, suggestion.plannedID != nil {
                        Button(action: onMove) {
                            Label(suggestion.moveTo.map { "Auf \($0.weekdayName)" } ?? "Verschieben",
                                  systemImage: "arrow.uturn.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
        .card()
    }

    private var icon: String {
        switch suggestion.kind {
        case .race: return "flag.checkered"
        case .done: return "checkmark.seal.fill"
        case .rest: return "bed.double.fill"
        case .train: return "figure.mixed.cardio"
        }
    }
}
