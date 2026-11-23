import SwiftData
import SwiftUI

/// Erster Start: Wettkampf festlegen, Verfügbarkeit, Health & Kalender verbinden, Plan erstellen.
struct OnboardingView: View {
    @Bindable var profile: AthleteProfile
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var calendar: CalendarManager
    @State private var step = 0
    @State private var level = LevelInfo(level: 1, xp: 0, levelStartXP: 0, nextLevelXP: 100)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $step) {
                    welcome.tag(0)
                    Form { RaceSettingsSection(profile: profile, onChange: {}) }.tag(1)
                    Form { AvailabilitySection(profile: profile, onChange: {}) }.tag(2)
                    connect.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button {
                    if step < 3 { withAnimation { step += 1 } } else { finish() }
                } label: {
                    Text(step < 3 ? "Weiter" : "Plan erstellen & loslegen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
            .navigationTitle(["Willkommen", "Dein Wettkampf", "Deine Zeit", "Verbindungen"][step])
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
        }
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            KonstiView(discipline: .run, level: level, speech: "Eeeellooo! Bereit für den Triathlon?", action: true, size: 200)
            Text("Konstis kesser Triathlon").font(.title.weight(.heavy))
            Text("Dein Trainingsplan bis zur Ziellinie: mit Vorschlägen, die sich an deine Form und deinen Kalender anpassen, und einem Pixel-Konsti, der mit jedem Training kesser wird.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
        }
        .padding()
    }

    private var connect: some View {
        Form {
            Section {
                Button {
                    Task {
                        try? await health.requestAuthorization()
                        profile.healthConnected = true
                    }
                } label: {
                    HStack {
                        Label("Apple Health verbinden", systemImage: "heart.fill")
                        Spacer()
                        if profile.healthConnected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                }
                .disabled(!health.isAvailable)
            } footer: {
                Text("Damit deine Watch-Trainings (Schwimmen, Rad, Laufen, Triathlon-Modus) automatisch in der App landen.")
            }
            Section {
                Button {
                    Task { profile.useCalendar = await calendar.requestAccess() }
                } label: {
                    HStack {
                        Label("Kalender verbinden", systemImage: "calendar")
                        Spacer()
                        if calendar.hasAccess { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                }
            } footer: {
                Text("Optional: Damit ich sehe, an welchen Tagen Arbeitstermine wenig Zeit lassen.")
            }
        }
    }

    private func finish() {
        PlanGenerator.regenerate(context: context, profile: profile)
        profile.onboardingDone = true
        try? context.save()
        Task { await WorkoutSync.importFromHealth(context: context, profile: profile, health: health) }
    }
}
