//
//  GoalEntity.swift
//  Linea
//
//  SwiftData persistence model for goals. Implementation detail of the local
//  repository; mapping to/from the `LineaGoal` domain type lives here.
//  New fields are optional (lightweight migration); nil = pre-migration
//  defaults (week horizon, start = createdAt, active).
//

import Foundation
import SwiftData

@Model
final class GoalEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var progress: Double
    var isCompleted: Bool
    var createdAt: Date

    /// Больше не используется: раньше цель имела горизонт «неделя/месяц».
    /// Колонка оставлена, чтобы обновление не стирало существующие цели — по
    /// ней вычисляется срок для тех, что были созданы до появления `endDate`.
    var horizonRaw: String?
    var startDate: Date?
    var endDate: Date?
    var isActive: Bool?
    /// Важность цели; nil у целей, сохранённых раньше, — средняя.
    var priorityRaw: String?
    /// Как Linea поняла цель при создании; у прежних целей — nil.
    var details: String?
    var currentState: String?
    var targetState: String?
    /// Признаки успеха, по одному на строку.
    var successCriteriaRaw: String?

    // Модель состояния и прогресс (ADR-036, ADR-037). Всё необязательное —
    // lightweight-миграция; nil у прежних целей: «Отмечаю сам» из слайдера.
    /// Стадии цели, по одной на строку.
    var stagesRaw: String?
    var stage: String?
    /// Этапы, числа и журнал продвижений — JSON (`DocumentCoding`): у них
    /// вложенная структура, а запросов внутрь нет.
    var milestonesData: Data?
    var metricsData: Data?
    var progressLogData: Data?
    var progressMethodRaw: String?
    var manualStateRaw: String?
    /// Чья цель (`scope`: personal, team, company). Имя колонки — с раунда 7,
    /// где здесь лежало «моя / команды / общая»; «общая» читается как команда.
    var ownerScopeRaw: String?
    /// За какую часть общей цели отвечает человек (`owner_scope`), текстом.
    var ownerScopeText: String?
    /// Свои числа у командной цели (вклад), JSON.
    var contributionMetricsData: Data?
    /// Тип, который выбрал человек; nil — как решит Linea.
    var kindOverrideRaw: String?
    var lastReviewedAt: Date?
    /// «Пока нет» на предложение вернуться к цели.
    var attentionSnoozedUntil: Date?
    /// Какой общей цель была — команды или компании (`sharedScope`); остаётся,
    /// когда человек выбрал «От меня».
    var sharedScopeRaw: String?
    /// Защищённое окно под цель (`GoalWindowPolicy`), JSON; nil — не разрешено.
    var protectedWindowData: Data?

    init(
        id: UUID,
        title: String,
        progress: Double,
        isCompleted: Bool,
        createdAt: Date,
        horizonRaw: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        isActive: Bool? = nil,
        priorityRaw: String? = nil,
        details: String? = nil,
        currentState: String? = nil,
        targetState: String? = nil,
        successCriteriaRaw: String? = nil,
        stagesRaw: String? = nil,
        stage: String? = nil,
        milestonesData: Data? = nil,
        metricsData: Data? = nil,
        progressLogData: Data? = nil,
        progressMethodRaw: String? = nil,
        manualStateRaw: String? = nil,
        ownerScopeRaw: String? = nil,
        ownerScopeText: String? = nil,
        contributionMetricsData: Data? = nil,
        kindOverrideRaw: String? = nil,
        lastReviewedAt: Date? = nil,
        attentionSnoozedUntil: Date? = nil,
        sharedScopeRaw: String? = nil,
        protectedWindowData: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.progress = progress
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.horizonRaw = horizonRaw
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        self.priorityRaw = priorityRaw
        self.details = details
        self.currentState = currentState
        self.targetState = targetState
        self.successCriteriaRaw = successCriteriaRaw
        self.stagesRaw = stagesRaw
        self.stage = stage
        self.milestonesData = milestonesData
        self.metricsData = metricsData
        self.progressLogData = progressLogData
        self.progressMethodRaw = progressMethodRaw
        self.manualStateRaw = manualStateRaw
        self.ownerScopeRaw = ownerScopeRaw
        self.ownerScopeText = ownerScopeText
        self.contributionMetricsData = contributionMetricsData
        self.kindOverrideRaw = kindOverrideRaw
        self.lastReviewedAt = lastReviewedAt
        self.attentionSnoozedUntil = attentionSnoozedUntil
        self.sharedScopeRaw = sharedScopeRaw
        self.protectedWindowData = protectedWindowData
    }
}

extension GoalEntity {
    convenience init(from goal: LineaGoal) {
        self.init(
            id: goal.id,
            title: goal.title,
            progress: goal.progress,
            isCompleted: goal.isCompleted,
            createdAt: goal.createdAt,
            startDate: goal.startDate,
            endDate: goal.endDate,
            isActive: goal.isActive,
            priorityRaw: goal.priority.rawValue,
            details: goal.details,
            currentState: goal.currentState,
            targetState: goal.targetState,
            successCriteriaRaw: Self.raw(goal.successCriteria),
            stagesRaw: Self.raw(goal.stages),
            stage: goal.stage,
            milestonesData: Self.encoded(goal.milestones),
            metricsData: Self.encoded(goal.metrics),
            progressLogData: Self.encoded(goal.progressLog),
            progressMethodRaw: goal.progressMethod.rawValue,
            manualStateRaw: goal.manualState?.rawValue,
            ownerScopeRaw: goal.scope.rawValue,
            ownerScopeText: goal.ownerScope,
            contributionMetricsData: Self.encoded(goal.contributionMetrics),
            kindOverrideRaw: goal.kindOverride?.rawValue,
            lastReviewedAt: goal.lastReviewedAt,
            attentionSnoozedUntil: goal.attentionSnoozedUntil,
            sharedScopeRaw: goal.sharedScope?.rawValue,
            protectedWindowData: Self.encodedValue(goal.protectedWindow)
        )
    }

    var domain: LineaGoal {
        LineaGoal(
            id: id,
            title: title,
            progress: progress,
            isCompleted: isCompleted,
            createdAt: createdAt,
            startDate: startDate ?? createdAt,
            endDate: endDate ?? Self.migratedEndDate(horizonRaw: horizonRaw, startDate: startDate ?? createdAt),
            isActive: isActive ?? true,
            priority: priorityRaw.flatMap(TaskPriority.init(rawValue:)) ?? .normal,
            details: details,
            currentState: currentState,
            targetState: targetState,
            successCriteria: Self.lines(successCriteriaRaw),
            stages: Self.lines(stagesRaw),
            stage: stage,
            milestones: Self.decoded([GoalMilestone].self, from: milestonesData) ?? [],
            metrics: Self.decoded([GoalMetric].self, from: metricsData) ?? [],
            progressMethod: progressMethodRaw.flatMap(GoalProgressMethod.init(rawValue:)) ?? .manual,
            manualState: manualStateRaw.flatMap(GoalManualState.init(rawValue:)),
            scope: GoalScope.legacy(ownerScopeRaw) ?? .personal,
            ownerScope: ownerScopeText,
            contributionMetrics: Self.decoded([GoalMetric].self, from: contributionMetricsData) ?? [],
            kindOverride: kindOverrideRaw.flatMap(GoalKind.init(rawValue:)),
            progressLog: Self.decoded([GoalProgressEvent].self, from: progressLogData) ?? [],
            sharedScope: sharedScopeRaw.flatMap(GoalScope.init(rawValue:)),
            lastReviewedAt: lastReviewedAt,
            attentionSnoozedUntil: attentionSnoozedUntil,
            protectedWindow: Self.decodedValue(GoalWindowPolicy.self, from: protectedWindowData)
        )
    }

    func apply(_ goal: LineaGoal) {
        title = goal.title
        progress = goal.progress
        isCompleted = goal.isCompleted
        startDate = goal.startDate
        endDate = goal.endDate
        isActive = goal.isActive
        priorityRaw = goal.priority.rawValue
        details = goal.details
        currentState = goal.currentState
        targetState = goal.targetState
        successCriteriaRaw = Self.raw(goal.successCriteria)
        applyState(goal)
    }

    /// Модель состояния и прогресс.
    private func applyState(_ goal: LineaGoal) {
        stagesRaw = Self.raw(goal.stages)
        stage = goal.stage
        milestonesData = Self.encoded(goal.milestones)
        metricsData = Self.encoded(goal.metrics)
        progressLogData = Self.encoded(goal.progressLog)
        progressMethodRaw = goal.progressMethod.rawValue
        manualStateRaw = goal.manualState?.rawValue
        ownerScopeRaw = goal.scope.rawValue
        ownerScopeText = goal.ownerScope
        contributionMetricsData = Self.encoded(goal.contributionMetrics)
        kindOverrideRaw = goal.kindOverride?.rawValue
        lastReviewedAt = goal.lastReviewedAt
        attentionSnoozedUntil = goal.attentionSnoozedUntil
        sharedScopeRaw = goal.sharedScope?.rawValue
        protectedWindowData = Self.encodedValue(goal.protectedWindow)
    }

    private static func encoded<Value: Encodable>(_ values: [Value]) -> Data? {
        guard !values.isEmpty else { return nil }
        return try? DocumentCoding.encoder().encode(values)
    }

    private static func encodedValue<Value: Encodable>(_ value: Value?) -> Data? {
        guard let value else { return nil }
        return try? DocumentCoding.encoder().encode(value)
    }

    private static func decodedValue<Value: Decodable>(_ type: Value.Type, from data: Data?) -> Value? {
        guard let data else { return nil }
        return try? DocumentCoding.decoder().decode(type, from: data)
    }

    /// Не прочиталось — пусто, а не потерянная цель.
    private static func decoded<Value: Decodable>(_ type: Value.Type, from data: Data?) -> Value? {
        guard let data else { return nil }
        return try? DocumentCoding.decoder().decode(type, from: data)
    }

    private static func raw(_ lines: [String]) -> String? {
        lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func lines(_ raw: String?) -> [String] {
        (raw ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Цель, созданная до появления явного срока, получает его из старого
    /// горизонта: конец той же недели или того же месяца.
    private static func migratedEndDate(horizonRaw: String?, startDate: Date) -> Date? {
        guard let horizonRaw else { return nil }
        let calendar = Calendar.current
        let component: Calendar.Component = horizonRaw == "week" ? .weekOfYear : .month
        let start = calendar.startOfDay(for: startDate)
        guard let next = calendar.date(byAdding: component, value: 1, to: start) else { return nil }
        return calendar.date(byAdding: .day, value: -1, to: next)
    }
}
