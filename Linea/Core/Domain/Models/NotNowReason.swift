//
//  NotNowReason.swift
//  Linea
//
//  «Почему не сейчас?» — иногда Linea спрашивает, почему человек отказался от
//  предложения (ADR-042). Компактно, четыре ответа:
//
//      Нет времени · Нет сил · Не хочется · Неактуально
//
//  Каждый что-то меняет в плане (`NotNowFeedback`). Не при каждом отказе —
//  только когда ответ помогает планировать.
//

import Foundation

nonisolated enum NotNowReason: String, Codable, CaseIterable, Hashable, Sendable {
    /// «Нет времени» — вернуться, когда задача поместится целиком.
    case noTime
    /// «Нет сил» — пока предлагать полегче.
    case noEnergy
    /// «Не хочется» — вернуться позже.
    case unwilling
    /// «Неактуально» — убрать из планов (с «Вернуть»).
    case irrelevant

    var title: String {
        switch self {
        case .noTime: return "Нет времени"
        case .noEnergy: return "Нет сил"
        case .unwilling: return "Не хочется"
        case .irrelevant: return "Неактуально"
        }
    }
}

/// Вопрос на экране — над следующим предложением «Сейчас».
nonisolated struct NotNowQuestion: Hashable, Sendable {
    let taskID: UUID
    /// «Почему не сейчас?»; у начатой — «Что помешало?»
    let title: String
    /// Задачу отпустили из работы («Не получается продолжить»).
    let wasStarted: Bool
    /// Предложение Linea, от которого отказались, если отказались от него.
    let suggestionID: UUID?

    var reasons: [NotNowReason] { NotNowReason.allCases }
}

/// Ответ на «Почему не сейчас?» — пишется в день, как остальные отклики.
nonisolated struct NotNowAnswer: Codable, Hashable, Sendable {
    let taskID: UUID
    let reason: NotNowReason
    /// Предложение, от которого отказались; nil — отказались не от предложения.
    let suggestionID: UUID?
    let wasStarted: Bool

    init(taskID: UUID, reason: NotNowReason, suggestionID: UUID? = nil, wasStarted: Bool = false) {
        self.taskID = taskID
        self.reason = reason
        self.suggestionID = suggestionID
        self.wasStarted = wasStarted
    }
}

nonisolated extension DayRecord {
    /// Когда Linea спрашивала «Почему не сейчас?» — и про какую задачу.
    var notNowQuestions: [(taskID: UUID, at: Date)] {
        feedback.compactMap { item in
            if case .notNowAsked(let taskID) = item.kind { return (taskID, item.at) }
            return nil
        }
    }

    /// Ответы на «Почему не сейчас?» — с моментом ответа.
    var notNowAnswers: [(answer: NotNowAnswer, at: Date)] {
        feedback.compactMap { item in
            if case .notNowReason(let answer) = item.kind { return (answer, item.at) }
            return nil
        }
    }

    /// Человек сказал «Нет сил» не раньше `minutes` назад: Linea пока
    /// предлагает полегче.
    func reportedLowEnergy(at moment: Date, within minutes: Int) -> Bool {
        notNowAnswers.contains { answer, at in
            answer.reason == .noEnergy && at <= moment && moment.timeIntervalSince(at) < TimeInterval(minutes * 60)
        }
    }
}
