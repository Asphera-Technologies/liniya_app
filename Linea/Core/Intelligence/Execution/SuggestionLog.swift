//
//  SuggestionLog.swift
//  Linea
//
//  Журнал предложений «Сейчас» в документе дня. Пока Linea предлагает одну и
//  ту же задачу, предложение одно; предложила другую — прежнее закрывается
//  без ответа (`replaced`), появляется новое. Ответ человека — «Начать»,
//  «Не сейчас», выбор в «Другое», закрытая задача — записывается в
//  предложение, и его id попадает в задачу (`LineaTask.suggestionID`).
//

import Foundation

nonisolated enum SuggestionLog {

    /// Предложение на экране, на которое ещё не ответили.
    static func open(in record: DayRecord) -> TaskSuggestion? {
        record.suggestions.last(where: \.isOpen)
    }

    /// «Сейчас» показало действие. Та же задача — ничего не меняется; другая —
    /// прежнее открытое закрывается как `replaced`, новое записывается с
    /// причиной, которую видел человек. Начатое действие и пустое «Сейчас»
    /// предложений не создают, а открытое закрывают.
    static func tracking(
        _ action: NextAction?,
        newID: UUID,
        isAlternative: Bool,
        in record: DayRecord,
        at moment: Date
    ) -> DayRecord {
        let current = open(in: record)
        guard let action, let option = action.option, !action.isStarted else {
            guard let current else { return record }
            return responding(.replaced, to: current.taskID, in: record, at: moment).record
        }
        if current?.taskID == option.taskID { return record }
        var result = record
        if let current {
            result = responding(.replaced, to: current.taskID, in: result, at: moment).record
        }
        let reason = action.facts.lazy.compactMap { fact -> NowReason? in
            if case .nowReason(let reason) = fact { return reason }
            return nil
        }.first
        result.suggestions.append(TaskSuggestion(
            id: newID, taskID: option.taskID, suggestedAt: moment,
            isAlternative: isAlternative, reason: reason
        ))
        return result
    }

    /// Пересчёт дня начинался с прочитанной раньше записи (`base`), а за это
    /// время Linea могла предложить новое и человек — ответить (`newer`, то,
    /// что в памяти). Ничего не теряется: новые предложения дописываются в
    /// конец — они позже всех прочитанных, — а ответ сильнее его отсутствия.
    static func merged(_ base: [TaskSuggestion], with newer: [TaskSuggestion]) -> [TaskSuggestion] {
        var result = base
        for suggestion in newer {
            if let index = result.firstIndex(where: { $0.id == suggestion.id }) {
                if result[index].isOpen, !suggestion.isOpen { result[index] = suggestion }
            } else {
                result.append(suggestion)
            }
        }
        return result
    }

    /// Ответ на открытое предложение этой задачи. Возвращает его id, а если
    /// открытого предложения этой задачи нет — nil, и день не меняется.
    static func responding(
        _ response: TaskSuggestion.Response,
        to taskID: UUID,
        in record: DayRecord,
        at moment: Date
    ) -> (record: DayRecord, suggestionID: UUID?) {
        guard let index = record.suggestions.lastIndex(where: { $0.isOpen && $0.taskID == taskID }) else {
            return (record, nil)
        }
        var result = record
        result.suggestions[index].response = response
        result.suggestions[index].respondedAt = moment
        return (result, result.suggestions[index].id)
    }
}
