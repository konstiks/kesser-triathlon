import SwiftUI

/// Kurze Start-Animation: Pixel-Konsti schwimmt, radelt und läuft durchs Bild.
struct IntroView: View {
    var onFinish: () -> Void

    @State private var index = -1
    @State private var showTitle = false
    @State private var bob = false
    @State private var finished = false

    private let steps: [(sprite: String, label: String, discipline: Discipline)] = [
        ("konsti_swim_action", "Schwimmen", .swim),
        ("konsti_bike_action", "Radfahren", .bike),
        ("konsti_run_action", "Laufen", .run),
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.38, blue: 0.86), Color(red: 0.05, green: 0.20, blue: 0.55)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                ZStack {
                    ForEach(steps.indices, id: \.self) { i in
                        if i == index {
                            Image(steps[i].sprite)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 220)
                                .offset(y: bob ? -6 : 4)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .leading).combined(with: .opacity),
                                    removal: .move(edge: .trailing).combined(with: .opacity)))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipped()

                // Fortschritt durch die drei Disziplinen
                HStack(spacing: 18) {
                    ForEach(steps.indices, id: \.self) { i in
                        VStack(spacing: 6) {
                            Image(systemName: steps[i].discipline.symbol)
                                .font(.title2.weight(.semibold))
                                .frame(width: 52, height: 52)
                                .background(i <= index ? steps[i].discipline.color : Color.white.opacity(0.15),
                                            in: RoundedRectangle(cornerRadius: 6))
                                .scaleEffect(i == index ? 1.15 : 1)
                            Text(steps[i].label)
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .opacity(i <= index ? 1 : 0.4)
                        }
                    }
                }
                .foregroundStyle(.white)

                Text("Konstis kesser Triathlon")
                    .font(.system(.title, design: .monospaced).weight(.heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(showTitle ? 1 : 0)
                    .scaleEffect(showTitle ? 1 : 0.8)
                Spacer()
                Text("Tippen zum Überspringen")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding()
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task {
            withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) { bob = true }
            for i in steps.indices {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { index = i }
                try? await Task.sleep(for: .milliseconds(900))
            }
            withAnimation(.spring) { showTitle = true }
            try? await Task.sleep(for: .milliseconds(900))
            finish()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Konstis kesser Triathlon")
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}
