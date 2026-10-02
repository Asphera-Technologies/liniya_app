//
//  GoalAnalyzing.swift
//  Linea
//
//  Разбор новой цели: сырую формулировку и рассказ человека — в «Я поняла
//  цель так» (`GoalUnderstanding`). Сейчас разбирают правила на телефоне
//  (`RuleBasedGoalAnalyzer`), как и итог дня (ADR-021). Модель, если
//  появится, подключается через этот же протокол.
//

import Foundation

nonisolated protocol GoalAnalyzing: Sendable {
    func analyze(_ input: GoalIntakeInput, profile: UserProfile, time: TimeContext) async -> GoalUnderstanding
}
