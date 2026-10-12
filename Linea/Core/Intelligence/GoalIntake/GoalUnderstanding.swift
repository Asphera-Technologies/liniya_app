//
//  GoalUnderstanding.swift
//  Linea
//
//  Новая цель: сначала понять, потом создать. Человек пишет, чего хочет
//  достичь, и, если хочет, рассказывает подробнее — текстом или голосом.
//  Linea приводит это к четырём вещам: название, «Сейчас» (с чего
//  начинаем), «Результат» (что будет, когда цель достигнута) и признаки,
//  по которым это проверить. Чего не хватает — спрашивает, но не больше
//  одного вопроса за раз. Цель создаётся только после «Всё верно».
//

import Foundation

/// Что человек сказал о цели: название, рассказ, ответы на вопросы.
nonisolated struct GoalIntakeInput: Hashable, Sendable {
    var title: String
    /// «Расскажи подробнее» — необязательно.
    var details: String
    /// Ответы на уточняющие вопросы.
    var answers: [GoalQuestion.Topic: String]
    /// Вопросы, которые человек пропустил: их больше не задаём.
    var skipped: Set<GoalQuestion.Topic>

    init(
        title: String,
        details: String = "",
        answers: [GoalQuestion.Topic: String] = [:],
        skipped: Set<GoalQuestion.Topic> = []
    ) {
        self.title = title
        self.details = details
        self.answers = answers
        self.skipped = skipped
    }
}

/// Один уточняющий вопрос — о самом важном, чего не хватает.
nonisolated struct GoalQuestion: Hashable, Sendable {
    nonisolated enum Topic: String, CaseIterable, Hashable, Sendable {
        /// Что будет означать, что цель достигнута. Без этого цель не проверить.
        case result
        /// С чего начинаем: что уже есть.
        case start
    }

    let topic: Topic
    let text: String
    let example: String

    static let result = GoalQuestion(
        topic: .result,
        text: "Как поймём, что цель достигнута?",
        example: "Например: 50 тестировщиков в TestFlight, первая оплата, релиз до 1 декабря."
    )

    static let start = GoalQuestion(
        topic: .start,
        text: "С чего начинаем — что уже есть?",
        example: "Например: есть прототип, идёт переработка онбординга. Или: начинаю с нуля."
    )

    static func about(_ topic: Topic) -> GoalQuestion {
        switch topic {
        case .result: return .result
        case .start: return .start
        }
    }
}

/// Как Linea поняла цель: быстрая цель показывает это под строкой, «Я поняла
/// цель так» — перед созданием, и всё можно поправить.
nonisolated struct GoalUnderstanding: Hashable, Sendable {
    var title: String
    /// «Сейчас»: с чего начинаем. nil — человек не рассказал.
    var currentState: String?
    /// «Результат»: что будет, когда цель достигнута.
    var targetState: String?
    /// Как поймём, что получилось: проверяемые признаки.
    var successCriteria: [String]
    /// Срок, если его назвали: «до 15-го октября», «к 1 декабря».
    var deadline: Date?
    /// Рассказ человека как есть, с ответами на вопросы, — остаётся в цели.
    var details: String?
    /// Чего не хватает больше всего. nil — понятно достаточно.
    var question: GoalQuestion?

    // Быстрая цель и модель состояния (ADR-035, ADR-036).
    /// Важность: сказанная («важно», «главная цель») или средняя.
    var priority: TaskPriority
    var isPrioritySaid: Bool
    /// Из строки что-то вырезано: срок, важность, «хочу».
    var isTitleUnderstood: Bool
    /// Тип цели (`goal_type`) — его Linea определяет сама.
    var kind: GoalKind
    var scope: GoalScope
    /// Сферу выбрал человек — она хранится; иначе Linea пересчитывает её сама.
    var isScopeChosen: Bool
    var owner: GoalOwnerScope
    /// Как считать прогресс: что есть в словах, иначе — как обычно для типа.
    var method: GoalProgressMethod
    var metrics: [GoalMetric]
    var milestones: [GoalMilestone]
    var stages: [String]
    /// Стадия — только если о ней сказано в «Сейчас».
    var stage: String?

    init(
        title: String,
        currentState: String? = nil,
        targetState: String? = nil,
        successCriteria: [String] = [],
        deadline: Date? = nil,
        details: String? = nil,
        question: GoalQuestion? = nil,
        priority: TaskPriority = .normal,
        isPrioritySaid: Bool = false,
        isTitleUnderstood: Bool = false,
        kind: GoalKind = .other,
        scope: GoalScope = .personal,
        isScopeChosen: Bool = false,
        owner: GoalOwnerScope = .personal,
        method: GoalProgressMethod = .manual,
        metrics: [GoalMetric] = [],
        milestones: [GoalMilestone] = [],
        stages: [String] = [],
        stage: String? = nil
    ) {
        self.title = title
        self.currentState = currentState
        self.targetState = targetState
        self.successCriteria = successCriteria
        self.deadline = deadline
        self.details = details
        self.question = question
        self.priority = priority
        self.isPrioritySaid = isPrioritySaid
        self.isTitleUnderstood = isTitleUnderstood
        self.kind = kind
        self.scope = scope
        self.isScopeChosen = isScopeChosen
        self.owner = owner
        self.method = method
        self.metrics = metrics
        self.milestones = milestones
        self.stages = stages
        self.stage = stage
    }

    var canCreate: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Цель, которую создают «Создать цель» и «Всё верно». Этапы и числа
    /// получают id от цели: у двух целей они не совпадут.
    func goal(id: UUID, createdAt: Date, time: TimeContext) -> LineaGoal {
        LineaGoal(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: createdAt,
            startDate: time.startOfDay(createdAt),
            endDate: deadline.map(time.startOfDay),
            priority: priority,
            details: Self.text(details),
            currentState: Self.text(currentState),
            targetState: Self.text(targetState),
            successCriteria: successCriteria
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            stages: stages,
            stage: stage,
            milestones: milestones.enumerated().map { index, milestone in
                GoalMilestone(id: DeterministicID.uuid(from: "\(id.uuidString)|milestone|\(index)"),
                              title: milestone.title, weight: milestone.weight, completedAt: milestone.completedAt)
            },
            metrics: metrics.enumerated().map { index, metric in
                GoalMetric(id: DeterministicID.uuid(from: "\(id.uuidString)|metric|\(index)"), unit: metric.unit,
                           start: metric.start, current: metric.current, target: metric.target, updatedAt: metric.updatedAt)
            },
            progressMethod: method,
            manualState: method == .manual ? .started : nil,
            ownerScope: owner,
            scopeOverride: isScopeChosen ? scope : nil,
            lastReviewedAt: createdAt
        )
    }

    private static func text(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
