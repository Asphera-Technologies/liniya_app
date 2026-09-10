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
                .tabItem { Image(systemName: "waveform.path.ecg").accessibilityLabel("Health") }

            ProfileView()
                .tag(AppTab.profile)
                .tabItem { Image(systemName: "person").accessibilityLabel("Profile") }
        }
        .tint(LineaColor.ink)
        .sheet(isPresented: $appState.isPresentingAI) {
            LineaAIView()
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
}
