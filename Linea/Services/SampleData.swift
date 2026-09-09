//
//  SampleData.swift
//  Linea
//
//  ⚠️ SAMPLE / PREVIEW DATA ONLY — and, after Phase 2, deliberately narrow.
//
//  Tasks, goals, and health metrics NO LONGER use this file: tasks/goals are
//  real (SwiftData via repositories) and health is real (HealthKit). What
//  remains here is limited to features that are out of Phase 2 scope:
//    • Today's schedule ("Дальше")            — future calendar integration
//    • the meal focus + Nutrition list         — future nutrition integration
//    • Profile list rows                       — future profile/settings
//    • Health sub-navigation rows              — placeholder navigation
//    • Linea AI greeting/suggestions           — future AI integration
//
//  All of it is reachable only through `SampleBackend` (see LineaBackend.swift).
//

import Foundation

enum SampleData {

    // MARK: Today — schedule (sample: calendar not integrated)

    static let schedule: [ScheduleItem] = [
        ScheduleItem(time: "14:00", title: "Свободно"),
        ScheduleItem(time: "16:00", title: "Работа")
    ]

    // MARK: Nutrition (sample: nutrition not integrated)

    static let mealFocus = MealFocus(period: "Сегодня", meal: "Обед")

    static let nutritionRows: [LineaRow] = [
        LineaRow(title: "Поиск", value: "Каталог и подбор"),
        LineaRow(title: "Рецепты"),
        LineaRow(title: "AI-планер", value: "Настроен"),
        LineaRow(title: "Меню на неделю"),
        LineaRow(title: "Корзина", value: "1 · 277 ₽"),
        LineaRow(title: "Постоянный список", value: "1"),
        LineaRow(title: "Привычки", value: "1"),
        LineaRow(title: "Что мне можно", value: "30 · только из списка"),
        LineaRow(title: "Предпочтения"),
        LineaRow(title: "Ограничения"),
        LineaRow(title: "История", value: "1")
    ]

    // MARK: Health sub-navigation (sample: placeholder navigation)

    static let healthRows: [LineaRow] = [
        LineaRow(title: "Контекст", value: "1"),
        LineaRow(title: "Документы"),
        LineaRow(title: "Питание")
    ]

    // MARK: Profile (sample: profile/settings not integrated)

    static let profileRows: [LineaRow] = [
        LineaRow(title: "О себе"),
        LineaRow(title: "Цели", value: "4"),
        LineaRow(title: "Здоровье", value: "1"),
        LineaRow(title: "Питание"),
        LineaRow(title: "Документы"),
        LineaRow(title: "Подключения", value: "2"),
        LineaRow(title: "AI", value: "Grok")
    ]

    // MARK: Linea AI (sample: assistant not integrated)

    static let aiGreeting = "Я Linea. Вижу твой день, здоровье и планы. Что нужно?"

    static let aiSuggestions: [String] = [
        "Составь план на сегодня",
        "Что приготовить на обед?",
        "Как мой сон на этой неделе?"
    ]
}
