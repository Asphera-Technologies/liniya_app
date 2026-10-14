//
//  GoalStepScope.swift
//  Linea
//
//  В каких рамках Linea предлагает шаги цели (ADR-038). У своей цели — вся
//  цель. У цели команды или компании — только часть человека (`owner_scope`):
//  «Довести выручку компании до 5 млн ₽» — это работа многих, а шаги
//  человеку — про его «Новые enterprise-клиенты и ключевые переговоры», не
//  про всю компанию.
//
//  Сейчас по этим рамкам Linea называет окно для цели («Оставить 30
//  минут», «найти окно завтра»). Разложить цель на задачи сможет только
//  языковая модель (вопрос 44); её вход — эти же рамки, а не цель целиком.
//

import Foundation

nonisolated struct GoalStepScope: Hashable, Sendable {
    let goalID: UUID
    let goalTitle: String
    let scope: GoalScope
    /// Часть человека — у общей цели, если он её назвал.
    let part: String?

    static func of(_ goal: LineaGoal) -> GoalStepScope {
        GoalStepScope(goalID: goal.id, goalTitle: goal.title, scope: goal.scope, part: goal.ownPart)
    }

    /// Шаги — про часть человека, а не про всю общую цель.
    var isOwnPart: Bool { part != nil }

    /// Что делать в окне для цели — так задача и называется: «Окно для цели
    /// «Запустить Линия Beta»», у общей цели — «Окно для своей части: Новые
    /// enterprise-клиенты и ключевые переговоры».
    var windowTitle: String {
        if let part { return "Окно для своей части: \(part)" }
        return "Окно для цели \(RussianText.quoted(goalTitle))"
    }

    /// Защищённое окно в плане (ADR-046): «Продвинуть «Linea Beta»», у общей
    /// цели — «Продвинуть свою часть: Новые enterprise-клиенты…».
    var advanceTitle: String {
        if let part { return "Продвинуть свою часть: \(part)" }
        return "Продвинуть \(RussianText.quoted(goalTitle))"
    }

    /// Текст для модели, которая когда-нибудь будет раскладывать цель на
    /// шаги: у общей цели — часть человека, а цель всех — только как фон.
    var decompositionBrief: String {
        guard let part else { return goalTitle }
        return "Моя часть: \(part). Общая цель (\(scope.title.lowercased())): \(goalTitle) — не моя работа целиком."
    }
}
