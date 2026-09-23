//
//  AssistantService.swift
//  Linea
//
//  Свободный разговор с моделью. Модель отвечает на вопросы пользователя,
//  опираясь на то, что Linea уже посчитала, и ничего не решает сама: план,
//  приоритеты и оценка сил остаются за детерминированным ядром.
//
//  Наружу уходят только производные факты — сколько человек спал, какой
//  сегодня совет по нагрузке, названия задач. Ни одного сырого замера из
//  HealthKit. И только если пользователь включил облачного ассистента в
//  «Профиле».
//

import Foundation

nonisolated struct AssistantService: Sendable {
    let client: LanguageModelClient

    init(client: LanguageModelClient) {
        self.client = client
    }

    nonisolated struct Context: Sendable {
        var state: UserState?
        var plan: DayPlan?
        var sleep: SleepInsight?
        var nutrition: NutritionProfile?
        var taskTitles: [String]
        /// Блок памяти из `UserContextBuilder`: факты о человеке и выжимки дней.
        var memory: String?
        var time: TimeContext

        init(
            state: UserState? = nil,
            plan: DayPlan? = nil,
            sleep: SleepInsight? = nil,
            nutrition: NutritionProfile? = nil,
            taskTitles: [String] = [],
            memory: String? = nil,
            time: TimeContext
        ) {
            self.state = state
            self.plan = plan
            self.sleep = sleep
            self.nutrition = nutrition
            self.taskTitles = taskTitles
            self.memory = memory
            self.time = time
        }
    }

    static let systemPrompt = """
    Ты Linea — спокойный личный ассистент. Отвечай по-русски, на «ты», коротко: \
    два-четыре предложения, без списков, если их не просят. \
    Опирайся только на факты из блоков «Контекст» и «Память». В «Памяти» — что человек рассказывал \
    раньше: используй это, но не пересказывай без нужды. Не придумывай чисел, которых там нет. \
    Не ставь диагнозов и не давай медицинских рекомендаций: если вопрос про здоровье, \
    говори о самочувствии и режиме, а за медициной отправляй к врачу. \
    План дня и приоритеты задач считает само приложение — ты их объясняешь, а не меняешь.
    """

    func answer(to question: String, context: Context) async throws -> String {
        try await client.complete(system: Self.systemPrompt, user: prompt(question: question, context: context))
    }

    /// Контекст собирается из уже посчитанного и остаётся читаемым: это же
    /// текст, который уходит наружу, и его должно быть не стыдно показать.
    func prompt(question: String, context: Context) -> String {
        var lines: [String] = []
        let time = context.time
        lines.append("Сейчас \(RussianText.clock(time.now, time: time)).")

        if let state = context.state {
            if let sleep = state.sleepNight {
                lines.append("Сон прошлой ночью: \(RussianText.hoursMinutes(seconds: sleep.asleepSeconds)).")
            }
            if let insight = context.sleep, insight.canCompare, let usual = insight.usualSeconds {
                lines.append("Обычно спит \(RussianText.hoursMinutes(seconds: usual)).")
            }
            lines.append("Совет по нагрузке на сегодня: \(Self.adviceText(state.loadAdvice)).")
            if state.confidence < 0.35 {
                lines.append("Данных о состоянии мало, выводы осторожные.")
            }
        } else {
            lines.append("Данных о состоянии нет.")
        }

        if let plan = context.plan, !plan.blocks.isEmpty {
            let blocks = plan.blocks
                .sorted { $0.start < $1.start }
                .map { "\(RussianText.clock($0.start, time: time)) \($0.title)" }
            lines.append("План дня: \(blocks.joined(separator: "; ")).")
        } else if !context.taskTitles.isEmpty {
            lines.append("Задачи на сегодня: \(context.taskTitles.joined(separator: "; ")).")
        } else {
            lines.append("Задач на сегодня нет.")
        }

        if let nutrition = context.nutrition, nutrition.hasConstraints {
            var parts: [String] = []
            if let diet = nutrition.dietType { parts.append("диета: \(diet)") }
            if !nutrition.restrictions.isEmpty { parts.append("ограничения: \(nutrition.restrictions.joined(separator: ", "))") }
            if !nutrition.excludedProducts.isEmpty { parts.append("не подходит: \(nutrition.excludedProducts.joined(separator: ", "))") }
            if !nutrition.preferredProducts.isEmpty { parts.append("подходит: \(nutrition.preferredProducts.joined(separator: ", "))") }
            lines.append("Питание — \(parts.joined(separator: "; ")).")
        }

        let memoryBlock = context.memory.map { $0.isEmpty ? "" : "\n\nПамять:\n\($0)" } ?? ""
        return """
        Контекст:
        \(lines.joined(separator: "\n"))\(memoryBlock)

        Вопрос: \(question)
        """
    }

    private static func adviceText(_ advice: LoadAdvice) -> String {
        switch advice {
        case .reduce: return "снизить нагрузку"
        case .normal: return "обычный ритм"
        case .push: return "можно взять больше"
        case .unknown: return "непонятно, данных не хватает"
        }
    }
}
