//
//  GoalUpdateStore.swift
//  Linea
//
//  «Обновить состояние» цели (ADR-047): что изменилось — текстом или голосом,
//  как Linea это поняла — и только после «Подтвердить» цель меняется. Разбор —
//  правилами на телефоне (`GoalUpdateReader`), голос — та же модель GigaAM,
//  что у быстрой задачи и цели; наружу ничего не уходит.
//

import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class GoalUpdateStore {
    /// Что сказал человек — до «Разобрать».
    var text = ""
    /// Как Linea поняла; nil — ещё не разбирали или нажали «Изменить».
    private(set) var proposal: GoalStateUpdate?
    private(set) var isSaving = false

    let dictation: VoiceDictation
    private let planStore: PlanStore
    private let reader = GoalUpdateReader()
    /// Цель, какой её видит карточка, когда открыли обновление.
    private var goal: LineaGoal?

    init(dictation: VoiceDictation, planStore: PlanStore) {
        self.dictation = dictation
        self.planStore = planStore
        dictation.onText = { [weak self] spoken in
            guard let self else { return }
            let typed = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.text = typed.isEmpty ? spoken : "\(typed) \(spoken)"
        }
    }

    var time: TimeContext { planStore.time }

    var canRead: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && dictation.phase == .idle
    }

    /// Открыть обновление для цели — с чистого листа.
    func begin(_ goal: LineaGoal) {
        self.goal = goal
        text = ""
        proposal = nil
        isSaving = false
        dictation.reset()
    }

    func end() {
        dictation.reset()
        proposal = nil
    }

    func toggleDictation() {
        dictation.toggle()
    }

    /// «Разобрать»: Linea показывает, как поняла. Цель пока не меняется.
    func read() {
        guard let goal, canRead else { return }
        dictation.cancel()
        let update = reader.read(text, goal: goal)
        proposal = update
        LineaLog.plan.notice("Обновить состояние: этапов \(update.items.count, privacy: .public), чисел \(update.metrics.count, privacy: .public), стадия \(update.stage != nil, privacy: .public)")
    }

    /// «Изменить»: снова к словам.
    func edit() {
        proposal = nil
    }

    /// «Подтвердить»: этапы, числа, стадия, «Что уже сделано» и ближайшие шаги
    /// меняются; прежнее «Что уже сделано» — в историю, закрытые этапы — в
    /// журнал продвижений, план пересчитывается. Возвращает сохранённую цель.
    func confirm() async -> LineaGoal? {
        guard let goal, let proposal, !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        let updated = reader.applied(proposal, to: goal, at: time.now)
        await planStore.saveGoal(updated)
        LineaLog.plan.notice("Обновить состояние: подтверждено")
        return planStore.goals.first { $0.id == goal.id }
    }

    /// Приложение свернули: записи в фоне нет.
    func appMovedToBackground() {
        dictation.appMovedToBackground()
    }
}
