//
//  RootView.swift
//  Linea
//
//  App-level navigation: an icon-only native tab bar across Linea's five
//  areas, with the ambient Linea AI surface presented over everything from
//  the command bar. Icon-only tabs keep the calm Linea character; each tab
//  carries an accessibility label for VoiceOver.
//

import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(IntelligenceStore.self) private var intelligence
    @Environment(CheckInStore.self) private var checkIn
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .today

    enum AppTab: Hashable {
        case today, plan, nutrition, health, profile
    }

    var body: some View {
        @Bindable var appState = appState

        TabView(selection: $selection) {
            TodayView()
                .tag(AppTab.today)
                .tabItem { Image(systemName: "calendar").accessibilityLabel("Сегодня") }

            PlanView()
                .tag(AppTab.plan)
                .tabItem { Image(systemName: "list.bullet").accessibilityLabel("План") }

            NutritionView()
                .tag(AppTab.nutrition)
                .tabItem { Image(systemName: "fork.knife").accessibilityLabel("Питание") }

            HealthView()
                .tag(AppTab.health)
                .tabItem { Image(systemName: "waveform.path.ecg").accessibilityLabel("Здоровье") }

            ProfileView()
                .tag(AppTab.profile)
                .tabItem { Image(systemName: "person").accessibilityLabel("Профиль") }
        }
        .tint(LineaColor.ink)
        // Coming back to the app is the moment to re-check the day: iOS runs
        // no code of ours at 14:30, so this is when a slipping plan is noticed.
        // The check-in never records in the background: leaving the app stops
        // the recording, and it is transcribed once the user is back.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                checkIn.appBecameActive()
                Task { await intelligence.refresh(reason: .appeared) }
            case .background:
                checkIn.appMovedToBackground()
            default:
                break
            }
        }
        .sheet(isPresented: $appState.isPresentingAI) {
            LineaAIView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $appState.isPresentingCheckIn) {
            CheckInView()
                .presentationDetents([.large])
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
        .environment(HealthKitManager())
        .environment(PlanStore.preview)
        .environment(NutritionStore.preview)
        .environment(UserProfileStore.preview)
        .environment(IntelligenceStore.preview)
        .environment(MemoryStore.preview)
        .environment(CheckInStore.preview)
        .environment(LocalSpeechModel())
}
