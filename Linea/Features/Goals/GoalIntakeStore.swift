//
//  GoalIntakeStore.swift
//  Linea
//
//  Новая цель — как новая задача (ADR-035): одна строка «Чего хочешь
//  достичь?», под ней — как Linea её поняла и чипы самого важного: срок,
//  важность, как считать прогресс, сфера. «Создать цель» — и всё.
//
//  Подробнее — по желанию (ADR-029): «Рассказать подробнее» ведёт в рассказ
//  текстом или голосом, один уточняющий вопрос, если без него цель не
//  понять, «Я поняла цель так» и «Всё верно». Выбор в чипах при этом не
//  теряется. Пока цель не создана, её нет.
//
//  Решает ядро (`QuickGoalDraft`, `GoalAnalyzing`): стор хранит ввод, шаги и
//  голос, а цель сохраняет через `PlanStore`.
//

import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class GoalIntakeStore {

    enum Step: Equatable {
        /// Быстрая цель: строка, чипы, «Создать цель».
        case quick
        /// «Чего хочешь достичь?» и «Расскажи подробнее».
        case describe
        /// Один уточняющий вопрос.
        case question(GoalQuestion)
        /// «Я поняла цель так».
        case review
        /// «Изменить»: правка понятого.
        case edit
    }

    /// Куда идёт надиктованное в быстрой цели: в строку или в «За какую часть
    /// отвечаешь ты?».
    enum DictationTarget: Equatable {
        case line
        case part
    }

    /// Правка «Я поняла цель так»: признаки — по одному на строку.
    struct Edits: Equatable {
        var title = ""
        var currentState = ""
        var targetState = ""
        var criteria = ""
        var hasDeadline = false
        var deadline = Date()
        /// Своя часть общей цели.
        var ownerScope = ""
    }

    /// Быстрая цель: строка и выбор в чипах. Выбор живёт и в подробном
    /// рассказе: что выбрано в чипе, сильнее сказанного.
    var draft = QuickGoalDraft()
    var title = ""
    var details = ""
    /// Ответ на текущий вопрос.
    var answer = ""
    var edits = Edits()
    private(set) var step: Step = .quick
    private(set) var understanding: GoalUnderstanding?
    private(set) var isThinking = false
    private(set) var isSaving = false

    /// Голос: строка, своя часть, рассказ о цели или ответ на вопрос.
    let dictation: VoiceDictation
    private(set) var dictationTarget: DictationTarget = .line

    private var answers: [GoalQuestion.Topic: String] = [:]
    private var skipped: Set<GoalQuestion.Topic> = []
    private let planStore: PlanStore
    private let analyzer: any GoalAnalyzing
    /// Строку быстрой цели разбирают правила — мгновенно, на каждую букву.
    private let lineAnalyzer = RuleBasedGoalAnalyzer()
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

    /// Что получится из строки и чипов прямо сейчас.
    var resolution: QuickGoalResolution {
        draft.resolve(profile: profileProvider(), time: time, analyzer: lineAnalyzer)
    }

    var canCreateQuick: Bool {
        !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving && dictation.phase != .transcribing
    }

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
        draft = QuickGoalDraft()
        title = ""
        details = ""
        answer = ""
        answers = [:]
        skipped = []
        understanding = nil
        edits = Edits()
        step = .quick
        dictationTarget = .line
        isThinking = false
        isSaving = false
        goalID = UUID()
    }

    /// Экран закрыт: запись стирается, начатое распознавание отменяется.
    func end() {
        dictation.reset()
    }

    // MARK: Быстрая цель

    /// Срок; nil — «Без срока».
    func chooseDeadline(_ moment: Date?) {
        draft.deadline = moment.map { .at($0) } ?? .noDeadline
    }

    func choosePriority(_ priority: TaskPriority) {
        draft.priority = priority
    }

    func chooseMethod(_ method: GoalProgressMethod) {
        draft.method = method
    }

    /// «От меня» / «От команды» / «От компании».
    func chooseScope(_ scope: GoalScope) {
        draft.scope = scope
    }

    /// Микрофон у строки или у «За какую часть отвечаешь ты?».
    func toggleDictation(for target: DictationTarget) {
        if dictation.phase == .idle { dictationTarget = target }
        dictation.toggle()
    }

    /// «Создать цель»: цель — такая, как её видно под строкой и в чипах.
    /// `true` — экран можно закрывать.
    func createQuick() async -> Bool {
        let resolution = self.resolution
        guard step == .quick, resolution.canCreate, canCreateQuick else { return false }
        isSaving = true
        dictation.cancel()
        let goal = resolution.goal(id: goalID, createdAt: time.now, time: time)
        await planStore.saveGoal(goal)
        LineaLog.plan.notice("Быстрая цель: срок \(goal.endDate == nil ? "нет" : "есть", privacy: .public), тип \(resolution.understanding.kind.rawValue, privacy: .public), прогресс \(goal.progressMethod.rawValue, privacy: .public)\(resolution.methodOrigin == .chosen ? " (выбран)" : "", privacy: .public), чья \(goal.scope.rawValue, privacy: .public), своя часть \(goal.ownPart == nil ? "нет" : "есть", privacy: .public)")
        return true
    }

    /// «Рассказать подробнее»: строка становится названием, дальше — рассказ,
    /// вопрос, «Я поняла цель так». Выбранное в чипах остаётся.
    func tellMore() {
        guard step == .quick, !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        dictation.reset()
        title = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        step = .describe
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

    /// «От меня» на вопросе о своей части: цель своя, части нет.
    func answerPersonal() async {
        guard case .question(let question) = step, question.topic == .owner, !isThinking else { return }
        draft.scope = .personal
        answer = ""
        dictation.reset()
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
            deadline: understanding.deadline ?? time.adding(days: 30, to: time.today),
            ownerScope: understanding.ownerScope ?? ""
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
        if understanding.scope.isShared { understanding.ownerScope = Self.text(edits.ownerScope) }
        // Поправленные слова — новые этапы, числа и стадия.
        self.understanding = understanding.restructured(methodChosen: draft.method != nil)
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
        // Выбор «чья цель» и своя часть из быстрой цели — тоже в разбор.
        let input = draft.input(details: details, answers: answers, skipped: skipped, title: title)
        let analyzed = await analyzer.analyze(input, profile: profileProvider(), time: time)
        // Выбранное в чипах быстрой цели сильнее сказанного в рассказе.
        let result = draft.resolution(of: analyzed).understanding
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
        case .quick where dictationTarget == .part:
            draft.ownerScope = Self.joined(draft.ownerScope, spoken)
        case .quick:
            draft.text = Self.joined(draft.text, spoken)
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
