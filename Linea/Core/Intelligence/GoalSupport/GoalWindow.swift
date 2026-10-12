//
//  GoalWindow.swift
//  Linea
//
//  Небольшое окно для цели — то, что ставит согласие на «Оставить 30 минут»
//  или «Да» (ADR-039, ADR-040): задача к цели на 30 минут сегодня или завтра.
//  Своего времени у неё нет — место найдёт план. Называется по рамкам шагов
//  цели (`GoalStepScope`): у своей цели — «Окно для цели «…»», у цели
//  команды — «Окно для своей части: …», а не вся работа компании.
//
//  Человек согласился на день, полчаса и цель — это его поля, Linea их сама
//  не перезапишет (`TaskOwnership`). Приоритет — средний: окно — мягкая
//  поддержка и не вытесняет обязательства дня; выше его поднимает связь с
//  важной целью (§16).
//

import Foundation

nonisolated enum GoalWindow {
    static func task(for goal: LineaGoal, offer: GoalOffer, id: UUID, time: TimeContext) -> LineaTask {
        LineaTask(
            id: id,
            title: GoalStepScope.of(goal).windowTitle,
            date: time.startOfDay(offer.day),
            priority: .normal,
            createdAt: time.now,
            estimatedMinutes: offer.minutes,
            cognitiveDemand: .normal,
            goalID: goal.id,
            userFields: [.day, .duration, .goal]
        )
    }
}

/// Тексты поддержки целей.
nonisolated enum GoalSupportText {
    /// «5 обязательств · 3 бытовых дела · 2 других дела · 0 шагов к целям» —
    /// пустых видов дел нет, шаги к целям — всегда.
    static func composition(_ composition: DayComposition) -> String {
        var parts: [String] = []
        if composition.obligations > 0 {
            parts.append("\(composition.obligations) " + RussianText.plural(composition.obligations, "обязательство", "обязательства", "обязательств"))
        }
        if composition.maintenance > 0 {
            parts.append("\(composition.maintenance) " + RussianText.plural(composition.maintenance, "бытовое дело", "бытовых дела", "бытовых дел"))
        }
        if composition.other > 0 {
            parts.append("\(composition.other) " + RussianText.plural(composition.other, "другое дело", "других дела", "других дел"))
        }
        parts.append("\(composition.goalSteps) " + RussianText.plural(composition.goalSteps, "шаг", "шага", "шагов") + " к целям")
        return parts.joined(separator: GoalProgressText.separator)
    }

    /// «четыре дня», «неделю», «две недели», «12 дней», «больше месяца».
    static func idle(days: Int) -> String {
        let words = [2: "два дня", 3: "три дня", 4: "четыре дня", 5: "пять дней", 6: "шесть дней", 7: "неделю",
                     8: "восемь дней", 9: "девять дней", 10: "десять дней", 14: "две недели", 21: "три недели"]
        if let word = words[days] { return word }
        if days >= 30 { return "больше месяца" }
        return "\(days) " + RussianText.plural(days, "день", "дня", "дней")
    }

    /// После «Оставить 30 минут»: где план нашёл время, если уже нашёл.
    static func balanceAccepted(_ offer: GoalOffer, plannedAt start: Date?, time: TimeContext) -> String {
        let base = "Оставила \(offer.minutes) минут для цели \(RussianText.quoted(offer.goalTitle))"
        guard let start else { return base + " — время найдёт план." }
        return base + " — сегодня в \(RussianText.clock(start, time: time))."
    }

    /// После «Да» на возврат к цели.
    static func returnAccepted(_ offer: GoalOffer) -> String {
        "Хорошо: завтра Linea найдёт для неё \(offer.minutes) минут."
    }
}
