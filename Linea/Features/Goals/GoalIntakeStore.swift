//
//  GoalIntakeStore.swift
//  Linea
//
//  Новая цель: сначала понять, потом создать (ADR-029). Шаги: «Новая цель» —
//  название и, если хочется, рассказ текстом или голосом; один уточняющий
//  вопрос, если без него цель не понять; «Я поняла цель так»; «Всё верно»
//  создаёт цель, «Изменить» даёт поправить понятое. До «Всё верно» цели нет,
//  и раскладывать её на шаги нечего.
//
//  Решает ядро (`GoalAnalyzing`): стор хранит ввод, шаги и голос, а цель
//  сохраняет через `PlanStore`.
//

import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class GoalIntakeStore {

    enum Step: Equatable {
        /// «Чего хочешь достичь?» и «Расскажи подробнее».
        case describe
        /// Один уточняющий вопрос.
        case question(GoalQuestion)
        /// «Я поняла цель так».
        case review
        /// «Изменить»: правка понятого.
        case edit
    }

    /// Правка «Я поняла цель так»: признаки — по одному на строку.
    struct Edits: Equatable {
        var title = ""
        var currentState = ""
        var targetState = ""
        var criteria = ""
        var hasDeadline = false
        var deadline = Date()
    }

    var title = ""
    var details = ""
    /// Ответ на текущий вопрос.
    var answer = ""
    var edits = Edits()
    private(set) var step: Step = .describe
    private(set) var understanding: GoalUnderstanding?
    private(set) var isThinking = false
    private(set) var isSaving = false

    /// Голос: рассказ о цели или ответ на вопрос.
    let dictation: VoiceDictation

    private var answers: [GoalQuestion.Topic: String] = [:]
    private var skipped: Set<GoalQuestion.Topic> = []
    private let planStore: PlanStore
    private let analyzer: any GoalAnalyzing
    private let profileProvider: @MainActor () -> UserProfile
    private let timeProvider: @MainActor () -> TimeContext
    /// Выбирается один раз на открытие: второе «Всё верно» не создаст копию.
    private var goalID = UUID()

    init(
        dictation: VoiceDictation,
        planStore: PlanStore,
        analyzer: any GoalAnalyzing = RuleBasedGoalAnalyzer(),
        profile: @escaping @MainActor () -> UserProfile = { .default },
        time: @escaping @MainActor () -> TimeContext = { .live }
    ) {
        self.dictation = dictation
        self.planStore = planStore
        self.analyzer = analyzer
        self.profileProvider = profile
        self.timeProvider = time
        dictation.onText = { [weak self] spoken in
            self?.appendSpoken(spoken)
        }
    }

    var time: TimeContext { timeProvider() }

    var canContinue: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking && dictation.phase == .idle
    }

    var canAnswer: Bool {
        !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking && dictation.phase == .idle
    }

    // MARK: Экран

    /// Открыть с чистого листа.
    func begin() {
        end()
        title = ""
        details = ""
        answer = ""
        answers = [:]
        skipped = []
        understanding = nil
        edits = Edits()
        step = .describe
        isThinking = false
        isSaving = false
        goalID = UUID()
    }

    /// Экран закрыт: запись стирается, начатое распознавание отменяется.
    func end() {
        dictation.reset()
    }

    // MARK: Шаги

    /// «Продолжить» после рассказа.
    func proceed() async {
        guard canContinue else { return }
        await analyze()
    }

    /// Ответ на вопрос.
    func answerQuestion() async {
        guard case .question(let question) = step, canAnswer else { return }
        answers[question.topic] = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        answer = ""
        await analyze()
    }

    /// «Пропустить»: этот вопрос больше не задаём.
    func skipQuestion() async {
        guard case .question(let question) = step, !isThinking else { return }
        skipped.insert(question.topic)
        answer = ""
        dictation.reset()
        await analyze()
    }

    /// «Изменить» на «Я поняла цель так».
    func startEditing() {
        guard let understanding else { return }
        edits = Edits(
            title: understanding.title,
            currentState: understanding.currentState ?? "",
            targetState: understanding.targetState ?? "",
            criteria: understanding.successCriteria.joined(separator: "\n"),
            hasDeadline: understanding.deadline != nil,
            deadline: understanding.deadline ?? time.adding(days: 30, to: time.today)
        )
        step = .edit
    }

    /// «Готово» в правке — снова «Я поняла цель так», уже с правками.
    func finishEditing() {
        guard var understanding else { return }
        let title = edits.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        understanding.title = title
        understanding.currentState = Self.text(edits.currentState)
        understanding.targetState = Self.text(edits.targetState)
        understanding.successCriteria = edits.criteria
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        understanding.deadline = edits.hasDeadline ? edits.deadline : nil
        self.understanding = understanding
        step = .review
    }

    /// «Всё верно»: цель создаётся только сейчас. `true` — экран можно закрывать.
    func confirm() async -> Bool {
        guard step == .review, let understanding, understanding.canCreate, !isSaving else { return false }
        isSaving = true
        dictation.cancel()
        let goal = understanding.goal(id: goalID, createdAt: time.now, time: time)
        await planStore.saveGoal(goal)
        // Раскладывать цель на шаги можно только отсюда — после «Всё верно».
        LineaLog.plan.notice("Новая цель: сейчас \(goal.currentState == nil ? "нет" : "есть", privacy: .public), результат \(goal.targetState == nil ? "нет" : "есть", privacy: .public), признаков \(goal.successCriteria.count, privacy: .public), вопросов \(self.answers.count, privacy: .public), пропущено \(self.skipped.count, privacy: .public)")
        return true
    }

    // MARK: Разбор

    private func analyze() async {
        isThinking = true
        dictation.cancel()
        let input = GoalIntakeInput(title: title, details: details, answers: answers, skipped: skipped)
        let result = await analyzer.analyze(input, profile: profileProvider(), time: time)
        isThinking = false
        understanding = result
        if let question = result.question {
            step = .question(question)
        } else {
            step = .review
        }
    }

    /// Сказанное дописывается туда, где человек сейчас пишет.
    private func appendSpoken(_ spoken: String) {
        guard !spoken.isEmpty else { return }
        switch step {
        case .describe:
            details = Self.joined(details, spoken)
        case .question:
            answer = Self.joined(answer, spoken)
        case .review, .edit:
            break
        }
    }

    private static func joined(_ typed: String, _ spoken: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? spoken : "\(trimmed) \(spoken)"
    }

    private static func text(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
