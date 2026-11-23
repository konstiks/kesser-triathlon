import SwiftUI

/// Die Pixel-Cheerleaderin feuert Konsti bei besonderen Ereignissen an.
struct CheerOverlay: View {
    let event: CheerEvent
    let moreCount: Int
    var onDismiss: () -> Void

    @State private var jump = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.45 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }

            ConfettiView()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Image("cheerleader")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 260)
                    .rotationEffect(.degrees(jump ? -4 : 4))
                    .offset(y: jump ? -18 : 0)
                    .zIndex(1)

                VStack(spacing: 10) {
                    Label(event.title, systemImage: event.symbol)
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .multilineTextAlignment(.center)
                    Text(event.message)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if moreCount > 0 {
                        Text("+ \(moreCount) weitere Erfolge seit dem letzten Mal")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button(action: close) {
                        Text("Danke! 🙌").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 6)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.25), radius: 0, x: 5, y: 5)
                )
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary, lineWidth: 3))
                .padding(.horizontal, 28)
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { appeared = true }
            withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) { jump = true }
        }
        .sensoryFeedback(.success, trigger: appeared)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Die Cheerleaderin feuert dich an: \(event.title). \(event.message)")
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.2)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
    }
}

/// Einfaches Pixel-Konfetti.
struct ConfettiView: View {
    private struct Piece {
        let x: Double, speed: Double, size: Double, sway: Double, phase: Double, color: Color
    }

    @State private var start = Date.now
    private let pieces: [Piece] = (0..<70).map { _ in
        Piece(x: .random(in: 0...1), speed: .random(in: 0.12...0.3), size: .random(in: 5...10),
              sway: .random(in: 10...40), phase: .random(in: 0...(2 * .pi)),
              color: [Color.blue, .white, .yellow, .orange, .green, .pink].randomElement()!)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                for p in pieces {
                    let y = (p.phase / (2 * .pi) + t * p.speed).truncatingRemainder(dividingBy: 1.1) - 0.05
                    let x = p.x * size.width + sin(t * 3 + p.phase) * p.sway
                    let rect = CGRect(x: x, y: y * size.height, width: p.size, height: p.size)
                    ctx.fill(Path(rect), with: .color(p.color))
                }
            }
        }
    }
}
