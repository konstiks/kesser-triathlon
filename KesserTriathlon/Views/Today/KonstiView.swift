import SwiftUI

/// Pixel-Konsti: trägt das Outfit der aktuellen Disziplin und wird mit jeder Stufe "kesser".
///
/// - Frischling: etwas blass
/// - Durchhalter: volle Farbe, Bronze-Medaille
/// - Ausdauer-Ass: Silber-Medaille, Glitzer
/// - Kesser Konsti: goldene Aura, Krone, Gold-Medaille
struct KonstiView: View {
    let discipline: Discipline
    let level: LevelInfo
    var speech: String? = nil
    var action: Bool = false
    var size: CGFloat = 190

    @State private var bounce = false
    @State private var glow = false

    var body: some View {
        VStack(spacing: 6) {
            if let speech {
                SpeechBubble(text: speech)
                    .transition(.scale.combined(with: .opacity))
            }
            ZStack {
                aura
                Image(action ? discipline.actionSprite : discipline.standingSprite)
                    .resizable()
                    .scaledToFit()
                    .frame(height: size)
                    .saturation(level.tier == .frischling ? 0.75 : 1)
                    .shadow(color: level.tier >= .durchhalter ? level.tier.color.opacity(0.5) : .clear, radius: 8)
                    .offset(y: bounce ? -4 : 2)
                    .overlay(alignment: .topTrailing) { medal }
                    .overlay(alignment: .top) { crown }
                if level.tier >= .ass { sparkles }
            }
            .frame(height: size + 20)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { bounce = true }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { glow = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pixel-Konsti im \(discipline.name)-Outfit, Stufe \(level.tier.name)")
    }

    @ViewBuilder private var aura: some View {
        if level.tier == .kesser {
            Circle()
                .fill(RadialGradient(colors: [Tier.kesser.color.opacity(glow ? 0.55 : 0.3), .clear],
                                     center: .center, startRadius: 10, endRadius: size * 0.7))
                .frame(width: size * 1.4, height: size * 1.4)
        } else if level.tier == .ass {
            Circle()
                .fill(RadialGradient(colors: [discipline.color.opacity(0.25), .clear],
                                     center: .center, startRadius: 10, endRadius: size * 0.6))
                .frame(width: size * 1.2, height: size * 1.2)
        }
    }

    @ViewBuilder private var medal: some View {
        if level.tier >= .durchhalter {
            Image(systemName: "medal.fill")
                .font(.system(size: size * 0.14))
                .foregroundStyle(level.tier.color)
                .shadow(radius: 2)
                .offset(x: 6, y: size * 0.25)
        }
    }

    @ViewBuilder private var crown: some View {
        if level.tier == .kesser {
            Image(systemName: "crown.fill")
                .font(.system(size: size * 0.16))
                .foregroundStyle(Tier.kesser.color)
                .shadow(color: .orange, radius: glow ? 6 : 2)
                .offset(y: -size * 0.1 + (bounce ? -4 : 2))
        }
    }

    private var sparkles: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: CGFloat(10 + (i % 3) * 5)))
                    .foregroundStyle(level.tier == .kesser ? Tier.kesser.color : .white)
                    .shadow(color: discipline.color, radius: 3)
                    .opacity(glow == (i % 2 == 0) ? 1 : 0.2)
                    .offset(x: CGFloat([-0.42, 0.45, -0.35, 0.38, 0.05][i]) * size,
                            y: CGFloat([-0.3, -0.2, 0.25, 0.35, -0.5][i]) * size)
            }
        }
    }
}

struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.12), radius: 0, x: 3, y: 3)
            )
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary, lineWidth: 2))
    }
}

/// Karte mit Pixel-Konsti, Level und XP-Balken.
struct KonstiCard: View {
    let level: LevelInfo
    let discipline: Discipline
    let speech: String
    let action: Bool
    @State private var outfit: Discipline?
    @State private var showLevels = false

    var body: some View {
        VStack(spacing: 12) {
            KonstiView(discipline: outfit ?? discipline, level: level, speech: speech, action: action)
                .onTapGesture {
                    // Tippen wechselt das Outfit
                    let all = Discipline.allCases
                    let current = outfit ?? discipline
                    let next = all[(all.firstIndex(of: current)! + 1) % all.count]
                    withAnimation(.spring) { outfit = next }
                }
            Button { showLevels = true } label: {
                VStack(spacing: 6) {
                    HStack {
                        Label(level.tier.name, systemImage: level.tier.symbol)
                            .font(.headline)
                            .foregroundStyle(level.tier == .frischling ? Color.primary : level.tier.color)
                        Spacer()
                        Text("Level \(level.level)").font(.headline.monospacedDigit())
                    }
                    PixelBar(value: level.fractionInLevel, color: level.tier == .frischling ? .accentColor : level.tier.color)
                    HStack {
                        Text("\(level.xp) XP").monospacedDigit()
                        Spacer()
                        Text(level.isMax ? "Maximum erreicht!" : "noch \(level.nextLevelXP - level.xp) XP bis Level \(level.level + 1)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .card()
        .sheet(isPresented: $showLevels) { LevelInfoSheet(level: level) }
    }
}

struct LevelInfoSheet: View {
    let level: LevelInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Für jedes Training gibt es XP: Minuten × Intensität, plus Bonus, wenn es zum Plan passt. Wer den Plan durchzieht, ist am Wettkampftag Level 20.")
                        .font(.subheadline)
                }
                Section("Stufen") {
                    ForEach(Tier.allCases, id: \.self) { tier in
                        HStack(spacing: 12) {
                            Image(systemName: tier.symbol)
                                .foregroundStyle(tier == .frischling ? Color.green : tier.color)
                                .frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(tier.name).font(.headline)
                                Text("Level \(tier.rawValue * 5 + 1)–\(tier.rawValue * 5 + 5) · \(tier.motto)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if tier == level.tier { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                    }
                }
            }
            .navigationTitle("Leveling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
