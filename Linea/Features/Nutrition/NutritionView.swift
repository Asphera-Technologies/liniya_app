//
//  NutritionView.swift
//  Linea
//
//  Экран «Питание»: ближайший приём пищи с кнопкой «Поел» и одна строка
//  настроек. Раньше настройки были разбросаны шестью строками — диета,
//  ограничения, продукты, особенности, время еды, — и экран выглядел как
//  список без смысла. Теперь это одна кнопка, а разделы живут внутри
//  редактора.
//
//  Эти значения использует всё остальное приложение: окна еды занимают время
//  в плане дня, подходящие продукты попадают в советы, а «Поел» кормит оценку
//  сил. Ничего медицинского здесь нет: особенности здоровья — это теги
//  пользователя, они только фильтруют подсказки.
//

import SwiftUI

struct NutritionView: View {
    @Environment(AppState.self) private var appState
    @Environment(NutritionStore.self) private var nutrition
    @Environment(\.openURL) private var openURL

    @State private var isEditingProfile = false

    var body: some View {
        NavigationStack {
            LineaScaffold(title: "Питание") {
                nextMealSection
                orderSection
                settingsSection
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
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    LineaOutlineButton(title: "Поел") {
                        Task { await nutrition.logMeal(meal.kind) }
                    }
                    LineaOutlineButton(title: "Подобрать") {
                        appState.openAI(prompt: "Подбери \(meal.kind.title.lowercased()) с учётом моих ограничений")
                    }
                }
            } else {
                Text("Всё отмечено")
                    .font(LineaFont.feature)
                    .foregroundStyle(LineaColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Заказ

    /// Корзина из подходящих продуктов. Заказ оформляется во ВкусВилле, но
    /// состав корзины собирает Linea — только так она знает, что человек взял:
    /// истории заказов каталог не отдаёт.
    @ViewBuilder
    private var orderSection: some View {
        if nutrition.isCatalogAvailable, !nutrition.allowedProducts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Заказ", trailing: "ВкусВилл")
                HStack(spacing: 12) {
                    LineaOutlineButton(title: nutrition.isBuildingCart ? "Собираю…" : "Собрать корзину") {
                        Task { await nutrition.buildCart() }
                    }
                    if let url = nutrition.cartURL {
                        LineaOutlineButton(title: "Открыть") { openURL(url) }
                    }
                }
                if let message = nutrition.cartMessage {
                    Text(message)
                        .font(LineaFont.caption)
                        .foregroundStyle(LineaColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Settings

    /// Одна кнопка вместо шести строк: внутри редактора те же разделы, но
    /// экран перестаёт быть списком одинаковых пунктов.
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Что мне можно")
            LineaListRow(title: "Настройки питания", value: settingsSummary) { isEditingProfile = true }
            LineaHairline()
            Text("Диета, ограничения, подходящие продукты, особенности здоровья и время приёмов пищи.")
                .font(LineaFont.caption)
                .foregroundStyle(LineaColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    /// Короткая сводка, чтобы строка не была пустой: диета или число правил.
    private var settingsSummary: String {
        if let diet = nutrition.profile.dietType, !diet.isEmpty { return diet }
        let rules = nutrition.profile.restrictions.count
            + nutrition.profile.excludedProducts.count
            + nutrition.profile.conditions.count
        return rules == 0 ? "Не заданы" : "Правил: \(rules)"
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

    private func clock(_ time: TimeOfDay) -> String {
        String(format: "%d:%02d", time.hour, time.minute)
    }
}
