//
//  TodayView.swift
//  Linea
//
//  The Today / Overview screen: a time-aware greeting, the day's single most
//  important REAL task (from PlanStore), what's next on the schedule, and the
//  next meal. Schedule and meal remain sample data (calendar & nutrition are
//  out of Phase 2 scope) and are tagged "Демо".
//

import SwiftUI

struct TodayView: View {
    @Environment(AppState.self) private var appState
    @Environment(PlanStore.self) private var plan

    private let backend: LineaBackend = SampleBackend()

    @State private var schedule: [ScheduleItem] = []
    @State private var meal: MealFocus?

    var body: some View {
        NavigationStack {
            LineaScaffold(title: greeting, subtitle: dateSubtitle) {
                mainToday
                upNext
                nutrition
            }
        }
        .task {
            await plan.load()
            schedule = await backend.schedule()
            meal = await backend.mealFocus()
        }
    }

    // MARK: Sections

    private var mainToday: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Главное сегодня")
            if let task = plan.topTaskToday {
                Text(task.title)
                    .font(LineaFont.feature)
                    .foregroundStyle(LineaColor.textPrimary)
            } else {
                Text("На сегодня задач нет")
                    .font(LineaFont.feature)
                    .foregroundStyle(LineaColor.textTertiary)
            }
        }
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Дальше", trailing: "Демо")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(schedule) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 20) {
                        Text(item.time)
                            .font(LineaFont.rowTitle)
                            .foregroundStyle(LineaColor.textTertiary)
                            .monospacedDigit()
                        Text(item.title)
                            .font(LineaFont.rowTitle)
                            .foregroundStyle(LineaColor.textPrimary)
                    }
                }
            }
        }
    }

    private var nutrition: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Питание", trailing: "Демо")
            Text(meal?.meal ?? "—")
                .font(LineaFont.feature)
                .foregroundStyle(LineaColor.textPrimary)
            LineaOutlineButton(title: "Подобрать") {
                appState.openAI(prompt: "Подбери \(meal?.meal.lowercased() ?? "обед")")
            }
        }
    }

    // MARK: Greeting

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Доброе утро"
        case 12..<18: return "Добрый день"
        case 18..<23: return "Добрый вечер"
        default: return "Доброй ночи"
        }
    }

    private var dateSubtitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE, d"
        return formatter.string(from: Date()).capitalizedFirst
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
