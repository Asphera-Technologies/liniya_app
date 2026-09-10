//
//  NutritionView.swift
//  Linea
//
//  The Nutrition ("Питание") screen. No longer a demo list: it shows the next
//  meal window with a one-tap «Поел», and opens the real profile editor —
//  diet, what is allowed and excluded, condition tags and meal times.
//
//  These are the values the rest of Linea uses: meal windows block time in the
//  day plan, allowed products fill the meal advice, and «Поел» feeds the
//  energy model. Nothing here is medical: conditions are user tags used as
//  filters only.
//

import SwiftUI

struct NutritionView: View {
    @Environment(AppState.self) private var appState
    @Environment(NutritionStore.self) private var nutrition

    @State private var isEditingProfile = false

    var body: some View {
        NavigationStack {
            LineaScaffold(title: "Питание") {
                nextMealSection
                constraintsSection
                loggedSection
            }
        }
        .task { await nutrition.load() }
        .sheet(isPresented: $isEditingProfile) {
            NutritionProfileEditor(profile: nutrition.profile) { updated in
                Task { await nutrition.save(updated) }
            }
        }
    }

    // MARK: Next meal

    @ViewBuilder
    private var nextMealSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "Сегодня")
            if let meal = nutrition.nextMeal {
                Text("\(meal.kind.title) в \(clock(meal.start))")
                    .font(LineaFont.feature)
                    .foregroundStyle(LineaColor.textPrimary)
                HStack(spacing: 12) {
                    LineaOutlineButton(title: "Поел") {
                        Task { await nutrition.logMeal(meal.kind) }
                    }
                    LineaOutlineButton(title: "Подобрать") {
                        appState.openAI(prompt: "Подбери \(meal.kind.title.lowercased()) с учётом моих ограничений")
                    }
                }
            } else {
                Text("Приёмы пищи на сегодня отмечены")
                    .font(LineaFont.feature)
                    .foregroundStyle(LineaColor.textTertiary)
            }
        }
    }

    // MARK: Constraints

    private var constraintsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Что мне можно")
            LineaListRow(title: "Диета", value: nutrition.profile.dietType ?? "Не задана") { isEditingProfile = true }
            LineaHairline()
            LineaListRow(title: "Ограничения", value: countText(nutrition.profile.restrictions.count)) { isEditingProfile = true }
            LineaHairline()
            LineaListRow(title: "Не подходит", value: countText(nutrition.profile.excludedProducts.count)) { isEditingProfile = true }
            LineaHairline()
            LineaListRow(title: "Подходит", value: countText(nutrition.profile.preferredProducts.count)) { isEditingProfile = true }
            LineaHairline()
            LineaListRow(title: "Особенности здоровья", value: countText(nutrition.profile.conditions.count)) { isEditingProfile = true }
            LineaHairline()
            LineaListRow(title: "Время приёмов пищи", value: countText(nutrition.profile.mealWindows.count)) { isEditingProfile = true }
        }
    }

    @ViewBuilder
    private var loggedSection: some View {
        if !nutrition.todaysMeals.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Отмечено сегодня")
                VStack(spacing: 0) {
                    ForEach(Array(nutrition.todaysMeals.enumerated()), id: \.element.id) { index, meal in
                        HStack {
                            Text(meal.kind.title)
                                .font(LineaFont.rowTitle)
                                .foregroundStyle(LineaColor.textPrimary)
                            Spacer(minLength: 8)
                            Text(clock(TimeContext.live.timeOfDay(of: meal.at)))
                                .font(LineaFont.rowValue)
                                .foregroundStyle(LineaColor.textTertiary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 14)
                        if index < nutrition.todaysMeals.count - 1 { LineaHairline() }
                    }
                }
            }
        }
    }

    private func countText(_ count: Int) -> String? {
        count == 0 ? "—" : "\(count)"
    }

    private func clock(_ time: TimeOfDay) -> String {
        String(format: "%d:%02d", time.hour, time.minute)
    }
}
