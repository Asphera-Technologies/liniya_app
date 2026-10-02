//
//  QuickAddStore.swift
//  Linea
//
//  Быстрое создание задачи: строка, чипы под ней, голос. Название —
//  единственное обязательное поле; остальное Linea берёт из сказанного или
//  ставит по умолчанию, а человек меняет чипом. Всё можно поправить потом в
//  карточке задачи.
//
//  Решает не стор, а ядро (`QuickTaskDraft`): стор хранит ввод, записывает
//  голос и сохраняет задачу через `PlanStore`. Голос — как в итоге дня:
//  распознаёт модель на телефоне, запись удаляется сразу после распознавания,
//  наружу ничего не уходит.
//

import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class QuickAddStore {

    typealias VoicePhase = VoiceDictation.Phase

    /// Строка ввода и выбор в чипах.
    var draft = QuickTaskDraft()
    private(set) var isSaving = false
    /// Чем станет задача без слов о дне: «Без даты» — входящие. «Когда?»
    /// Linea не спрашивает; место задаче подберёт план или разбор.
    private(set) var defaultDay: TaskDay? = .someday

    /// Голос: запись и распознавание на телефоне; сказанное дописывается в строку.
    let dictation: VoiceDictation

    private let planStore: PlanStore
    private let profileProvider: @MainActor () -> UserProfile
    private let timeProvider: @MainActor () -> TimeContext
    /// Выбирается один раз на открытие: второе «Добавить» не создаст копию.
    private var taskID = UUID()

    init(
        recorder: VoiceRecorder,
        planStore: PlanStore,
        hasSpeechModel: Bool = false,
        makeTranscriber: @escaping @MainActor () -> any SpeechTranscribing,
        profile: @escaping @MainActor () -> UserProfile = { .default },
        time: @escaping @MainActor () -> TimeContext = { .live }
    ) {
        self.dictation = VoiceDictation(
            recorder: recorder,
            hasSpeechModel: hasSpeechModel,
            makeTranscriber: makeTranscriber,
            subject: "Задача",
            fallbackNotice: "Распознала системная диктовка — проверь название."
        )
        self.planStore = planStore
        self.profileProvider = profile
        self.timeProvider = time
        dictation.onText = { [weak self] spoken in
            guard let self else { return }
            let typed = self.draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Сказанное дописывается к набранному: «Отчёт» + «завтра к шести».
            self.draft.text = typed.isEmpty ? spoken : "\(typed) \(spoken)"
        }
    }

    var time: TimeContext { timeProvider() }

    // Голос — как у экрана: фаза, пояснение, запись.
    var voice: VoicePhase { dictation.phase }
    var notice: String? { dictation.notice }
    var recorder: VoiceRecorder { dictation.recorder }
    var hasSpeechModel: Bool { dictation.hasSpeechModel }

    /// Что получится из ввода прямо сейчас — это и показывают чипы.
    var resolution: QuickTaskResolution {
        draft.resolve(goals: planStore.goals, profile: profileProvider(), time: time, defaultDay: defaultDay)
    }

    /// Цели, к которым можно привязать задачу.
    var activeGoals: [LineaGoal] { planStore.activeGoals }

    func goal(with id: UUID?) -> LineaGoal? {
        guard let id else { return nil }
        return planStore.goals.first { $0.id == id }
    }

    // MARK: Экран

    /// Открыть ввод с чистого листа.
    func begin(defaultDay: TaskDay? = .someday) {
        end()
        self.defaultDay = defaultDay
    }

    /// Экран закрыт: запись стирается, начатое распознавание отменяется.
    func end() {
        dictation.reset()
        draft = QuickTaskDraft()
        isSaving = false
        taskID = UUID()
    }

    // MARK: Чипы

    func chooseDay(_ day: TaskDay) {
        draft.day = day
    }

    /// Срок с часами; `nil` — «Без срока».
    func chooseDeadline(_ moment: Date?) {
        if let moment {
            draft.deadline = .at(moment)
        } else {
            draft.deadline = .noDeadline
        }
    }

    func chooseMinutes(_ minutes: Int) {
        draft.minutes = minutes
    }

    func choosePriority(_ priority: TaskPriority) {
        draft.priority = priority
    }

    /// Цель; `nil` — «Без цели».
    func chooseGoal(_ id: UUID?) {
        if let id {
            draft.goal = .linked(id)
        } else {
            draft.goal = .noGoal
        }
    }

    // MARK: Сохранение

    /// «Добавить». `true` — задача сохранена, экран можно закрывать.
    func save() async -> Bool {
        let resolution = self.resolution
        guard resolution.canSave, !isSaving else { return false }
        isSaving = true
        dictation.cancel()
        let task = resolution.task(id: taskID, createdAt: time.now)
        await planStore.saveTask(task)
        let parts = resolution.recognized.map(\.part.rawValue).joined(separator: ",")
        LineaLog.plan.notice("Быстрая задача: распознано [\(parts, privacy: .public)], цель \(resolution.goalID == nil ? "нет" : "есть", privacy: .public)")
        return true
    }

    // MARK: Голос

    /// Кнопка микрофона: начать запись, закончить её или ничего, пока идёт распознавание.
    func toggleVoice() {
        dictation.toggle()
    }

    /// Приложение свернули: записи в фоне нет, задачу проще надиктовать заново.
    func appMovedToBackground() {
        dictation.appMovedToBackground()
    }
}
