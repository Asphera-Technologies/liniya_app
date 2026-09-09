//
//  NutritionView.swift
//  Linea
//
//  The Nutrition ("Питание") screen: today's meal with quick actions, then a
//  hairline-separated list of nutrition areas — mirroring the Linea reference.
//

import SwiftUI

struct NutritionView: View {
    @Environment(AppState.self) private var appState
    private let backend: LineaBackend = SampleBackend()

    @State private var meal: MealFocus?
    @State private var rows: [LineaRow] = []

    var body: some View {
        NavigationStack {
            LineaScaffold(title: "Питание") {
                todaySection
                LineaRowList(rows: rows)
            }
        }
        .task { await load() }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: meal?.period ?? "Сегодня")
            Text(meal?.meal ?? "—")
                .font(LineaFont.feature)
                .foregroundStyle(LineaColor.textPrimary)
            HStack(spacing: 12) {
                LineaOutlineButton(title: "Подобрать") {
                    appState.openAI(prompt: "Подбери \(meal?.meal.lowercased() ?? "обед")")
                }
                LineaOutlineButton(title: "Составить меню на неделю") {
                    appState.openAI(prompt: "Составь меню на неделю")
                }
            }
        }
    }

    private func load() async {
        meal = await backend.mealFocus()
        rows = await backend.nutritionSections()
    }
}

#Preview {
    NutritionView()
        .environment(AppState())
}
