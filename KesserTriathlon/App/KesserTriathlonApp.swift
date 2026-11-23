import SwiftData
import SwiftUI

@main
struct KesserTriathlonApp: App {
    @StateObject private var health = HealthKitManager()
    @StateObject private var calendar = CalendarManager()

    /// Datenbank. Falls sie nach einem Update nicht geöffnet werden kann, wird sie neu angelegt,
    /// statt dass die App abstürzt (Watch-Trainings kommen danach wieder aus Apple Health).
    private let container: ModelContainer = {
        let schema = Schema([AthleteProfile.self, PlannedWorkout.self, CompletedWorkout.self])
        do {
            return try ModelContainer(for: schema)
        } catch {
            let base = URL.applicationSupportDirectory.appending(path: "default.store").path
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(atPath: base + suffix)
            }
            do {
                return try ModelContainer(for: schema)
            } catch {
                fatalError("Datenbank konnte nicht angelegt werden: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(health)
                .environmentObject(calendar)
                .environment(\.locale, Locale(identifier: "de_DE"))
        }
        .modelContainer(container)
    }
}

/// Stellt sicher, dass es genau ein Profil gibt, und zeigt beim ersten Start das Onboarding.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var health: HealthKitManager
    @Query private var profiles: [AthleteProfile]
    @State private var showIntro = true

    var body: some View {
        ZStack {
            content
            if showIntro {
                IntroView {
                    withAnimation(.easeOut(duration: 0.35)) { showIntro = false }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let profile = profiles.first {
            MainTabView(profile: profile)
                .fullScreenCover(isPresented: .constant(!profile.onboardingDone && !showIntro)) {
                    OnboardingView(profile: profile)
                }
                .sheet(isPresented: .constant(profile.onboardingDone && !profile.fitnessSetupDone && !showIntro)) {
                    FitnessCheckSheet(profile: profile)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await WorkoutSync.importFromHealth(context: context, profile: profile, health: health) }
                    }
                }
                .task {
                    // Nach einem App-Update mit neuer Plan-Logik den Plan automatisch neu erstellen
                    if profile.onboardingDone && profile.planVersion < PlanGenerator.currentVersion {
                        PlanGenerator.regenerate(context: context, profile: profile)
                    }
                    await WorkoutSync.importFromHealth(context: context, profile: profile, health: health)
                }
        } else {
            ProgressView()
                .onAppear {
                    context.insert(AthleteProfile())
                    try? context.save()
                }
        }
    }
}

struct MainTabView: View {
    let profile: AthleteProfile
    @Environment(\.modelContext) private var context
    @Query private var planned: [PlannedWorkout]
    @Query private var completed: [CompletedWorkout]

    var body: some View {
        let level = ProgressEngine.level(completed: completed, planned: planned)
        let pending = profile.onboardingDone
            ? CheerEngine.pending(completed: completed, planned: planned, profile: profile, level: level)
            : []
        TabView {
            TodayView(profile: profile)
                .tabItem { Label("Heute", systemImage: "sun.max.fill") }
            PlanView(profile: profile)
                .tabItem { Label("Plan", systemImage: "calendar") }
            FortschrittView(profile: profile)
                .tabItem { Label("Fortschritt", systemImage: "chart.bar.fill") }
            SettingsView(profile: profile)
                .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
        }
        .tint(Color.accentColor)
        .overlay {
            if let event = pending.first {
                CheerOverlay(event: event, moreCount: pending.count - 1) {
                    // Alle offenen Ereignisse als gefeiert markieren, damit es nicht nervt
                    profile.seenCheerIDs.append(contentsOf: pending.map(\.id))
                    try? context.save()
                }
                .id(event.id)
            }
        }
    }
}
