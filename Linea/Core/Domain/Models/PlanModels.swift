//
//  PlanModels.swift
//  Linea
//
//  Domain models for Plan (tasks & goals). These are plain, persistence-
//  agnostic value types. The UI and repositories speak *these* types — never
//  SwiftData `@Model` objects directly — so a remote repository can later be
//  dropped in without touching feature UI.
//
//  Time semantics of a task (deliberately three different things):
//    • `date`           — the DAY the user planned to do it (nil = «Без дня»);
//    • `deadline`       — the moment it must be done by (drives urgency);
//    • `scheduledStart` — a fixed start the user chose («Тренировка 17:00»);
//                         such a task is a commitment, the planner won't move it.
//  Where the planner PUTS a task lives in `DayPlan`, never in the task.
//

import Foundation

/// Приоритет задачи: низкий, средний, высокий.
///
/// Сырые значения (`low`/`normal`/`important`) намеренно оставлены прежними —
/// по ним читаются уже сохранённые задачи. Пользователь видит только `title`.
nonisolated enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case low
    case normal
    case important

    var isImportant: Bool { self == .important }

    var title: String {
        switch self {
        case .low: return "Низкий"
        case .normal: return "Средний"
        case .important: return "Высокий"
        }
    }

    /// Importance component for scoring, 0…1.
    var score: Double {
        switch self {
        case .low: return 0.2
        case .normal: return 0.5
        case .important: return 1.0
        }
    }
}

/// How much focused mental effort a task needs — the input to `energyFit`.
nonisolated enum CognitiveDemand: String, Codable, CaseIterable, Sendable {
    case light
    case normal
    case deep

    /// Demand on a 0…1 scale (brief: письма 0.3 / презентация 0.9).
    var score: Double {
        switch self {
        case .light: return 0.3
        case .normal: return 0.6
        case .deep: return 0.9
        }
    }

    var title: String {
        switch self {
        case .light: return "Лёгкая"
        case .normal: return "Обычная"
        case .deep: return "Сложная"
        }
    }
}

/// Как выбрано место задачи после «Перенести» (`reschedule_mode`). Нет
/// значения — день выбрал человек (`manual`).
nonisolated enum RescheduleMode: String, Codable, Hashable, Sendable {
    /// «Пусть Linea решит»: день и окно выбирает Linea и сама переставляет
    /// задачу, если её день прошёл, а она не сделана (`AutoReschedule`).
    case automatic
    /// «Позже сегодня»: день — сегодня, окно позже нашла Linea.
    case laterToday
}

/// A single task/plan item.
nonisolated struct LineaTask: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var title: String
    var notes: String?
    /// The day the task is assigned to. `nil` — без дня; без дня и срока —
    /// «Без даты» (входящие, `InboxReview`).
    var date: Date?
    var priority: TaskPriority
    var isDone: Bool
    var createdAt: Date

    // Intelligence inputs (all optional / defaulted → additive persistence change)
    var deadline: Date?
    var scheduledStart: Date?
    var estimatedMinutes: Int?
    var cognitiveDemand: CognitiveDemand
    var goalID: UUID?
    var completedAt: Date?
    /// Тип, который человек выбрал сам в карточке задачи. `nil` — тип
    /// определяет Linea (`TaskClassifier`), и он меняется вместе с названием.
    var kindOverride: TaskKind?
    /// Сколько раз задачу, которую пора было делать, переносили на потом
    /// (`TaskDeferral`): задача «зависает» — Linea поднимает её важность.
    var deferralCount: Int
    /// «Сначала нужно»: задачи, без которых эту не начать. Пока они открыты,
    /// план не поставит эту задачу раньше них.
    var blockedBy: [UUID]
    /// Когда человек разобрал задачу из «Без даты» и оставил её там: Linea
    /// больше не предлагает разобрать её снова (`InboxReview`).
    var inboxReviewedAt: Date?
    /// Параметры, которые человек задал сам: сказал при создании, выбрал в
    /// чипе или поменял потом. Linea их сама не перезаписывает
    /// (`TaskOwnership`). `nil` — задача сохранена раньше, чем Linea стала
    /// это помнить: тогда всё в ней считается заданным человеком.
    var userFields: Set<TaskField>?

    // Выполнение (`TaskLifecycle`, состояние — `status(at:)`): что человек
    // делал с задачей на самом деле.
    /// «Начать»: когда человек взялся за задачу. «Не сейчас» снимает.
    var startedAt: Date?
    /// Сколько задача заняла на самом деле: от «Начать» до «Завершить».
    /// `nil` — её не начинали или забыли завершить вовремя.
    var actualMinutes: Int?
    /// Предложение Linea, которое человек принял, взявшись за задачу или
    /// закрыв её (`TaskSuggestion`).
    var suggestionID: UUID?
    /// «Не сейчас»: до этого момента Linea её не предлагает и не ставит в план.
    var deferredUntil: Date?
    /// Человек убрал задачу из планов. Она не показывается, но остаётся в
    /// данных: отменённое — тоже поведение.
    var cancelledAt: Date?
    /// Кто выбрал место задачи после «Перенести»: «Пусть Linea решит» —
    /// Linea, и она же переставит задачу, если день прошёл. `nil` — человек.
    var rescheduleMode: RescheduleMode?
    /// Откуда `estimatedMinutes` (`estimated_duration_source`): сказал
    /// человек, оценила Linea по словам или по истории (`DurationEstimator`).
    /// `nil` у задач, сохранённых раньше: есть оценка — она человека.
    var estimatedDurationSource: DurationSource?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        date: Date? = nil,
        priority: TaskPriority = .normal,
        isDone: Bool = false,
        createdAt: Date = Date(),
        deadline: Date? = nil,
        scheduledStart: Date? = nil,
        estimatedMinutes: Int? = nil,
        cognitiveDemand: CognitiveDemand = .normal,
        goalID: UUID? = nil,
        completedAt: Date? = nil,
        kindOverride: TaskKind? = nil,
        deferralCount: Int = 0,
        blockedBy: [UUID] = [],
        inboxReviewedAt: Date? = nil,
        userFields: Set<TaskField>? = nil,
        startedAt: Date? = nil,
        actualMinutes: Int? = nil,
        suggestionID: UUID? = nil,
        deferredUntil: Date? = nil,
        cancelledAt: Date? = nil,
        rescheduleMode: RescheduleMode? = nil,
        estimatedDurationSource: DurationSource? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.date = date
        self.priority = priority
        self.isDone = isDone
        self.createdAt = createdAt
        self.deadline = deadline
        self.scheduledStart = scheduledStart
        self.estimatedMinutes = estimatedMinutes
        self.cognitiveDemand = cognitiveDemand
        self.goalID = goalID
        self.completedAt = completedAt
        self.kindOverride = kindOverride
        self.deferralCount = max(0, deferralCount)
        self.blockedBy = blockedBy
        self.inboxReviewedAt = inboxReviewedAt
        self.userFields = userFields
        self.startedAt = startedAt
        self.actualMinutes = actualMinutes
        self.suggestionID = suggestionID
        self.deferredUntil = deferredUntil
        self.cancelledAt = cancelledAt
        self.rescheduleMode = rescheduleMode
        self.estimatedDurationSource = estimatedDurationSource
    }

    /// Мягкое чтение: задачи лежат и в документах дня (`DayRecord`), и
    /// запись, сделанная до появления поля, должна читаться — иначе пропал бы
    /// весь день с его планом и ответами.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        date = try container.decodeIfPresent(Date.self, forKey: .date)
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .normal
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        scheduledStart = try container.decodeIfPresent(Date.self, forKey: .scheduledStart)
        estimatedMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        cognitiveDemand = try container.decodeIfPresent(CognitiveDemand.self, forKey: .cognitiveDemand) ?? .normal
        goalID = try container.decodeIfPresent(UUID.self, forKey: .goalID)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        kindOverride = try container.decodeIfPresent(TaskKind.self, forKey: .kindOverride)
        deferralCount = try container.decodeIfPresent(Int.self, forKey: .deferralCount) ?? 0
        blockedBy = try container.decodeIfPresent([UUID].self, forKey: .blockedBy) ?? []
        inboxReviewedAt = try container.decodeIfPresent(Date.self, forKey: .inboxReviewedAt)
        userFields = try container.decodeIfPresent(Set<TaskField>.self, forKey: .userFields)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        actualMinutes = try container.decodeIfPresent(Int.self, forKey: .actualMinutes)
        suggestionID = try container.decodeIfPresent(UUID.self, forKey: .suggestionID)
        deferredUntil = try container.decodeIfPresent(Date.self, forKey: .deferredUntil)
        cancelledAt = try container.decodeIfPresent(Date.self, forKey: .cancelledAt)
        rescheduleMode = try container.decodeIfPresent(RescheduleMode.self, forKey: .rescheduleMode)
        estimatedDurationSource = try? container.decodeIfPresent(DurationSource.self, forKey: .estimatedDurationSource)
    }

    /// Оценку дала Linea, а не человек: её можно уточнять самой.
    var isDurationEstimatedByLinea: Bool {
        estimatedDurationSource == .ai || estimatedDurationSource == .learned
    }

    // Duration without the user's estimate depends on what the task is —
    // see `TaskEstimate` (Intelligence) and `TaskKind.typicalMinutes`.

    /// A task with a user-chosen start is a commitment for the planner.
    var isFixed: Bool { scheduledStart != nil }

    /// Параметр задал человек — Linea его сама не меняет. У задачи,
    /// сохранённой до того, как Linea стала это помнить, — любой.
    func isSetByUser(_ field: TaskField) -> Bool {
        userFields?.contains(field) ?? true
    }
}

/// Цель: желаемый результат и то, где человек сейчас относительно него.
nonisolated struct LineaGoal: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var title: String
    /// Прежний ручной прогресс (слайдер), 0…1. Новые цели его не используют:
    /// прогресс считает `GoalProgressEngine` по методу цели. У целей,
    /// созданных раньше, из него следует состояние «Отмечаю сам».
    var progress: Double
    var isCompleted: Bool
    var createdAt: Date

    // Intelligence inputs
    /// Start of the goal period; defaults to the creation day.
    var startDate: Date
    /// Когда цель должна быть достигнута. `nil` — срок не задан: цель просто
    /// активна, и связанные с ней задачи получают ровный приоритет.
    var endDate: Date?
    var isActive: Bool
    /// Насколько цель важна сама по себе (`goal_importance`): задачи важной
    /// цели поднимаются выше. Подписи — «Низкая / Средняя / Высокая».
    var priority: TaskPriority

    // Как Linea поняла цель при создании (`GoalUnderstanding`). У целей,
    // созданных раньше, — пусто.
    /// Рассказ человека своими словами, текстом или голосом.
    var details: String?
    /// «Сейчас»: с чего начинаем.
    var currentState: String?
    /// «Результат»: что будет, когда цель достигнута.
    var targetState: String?
    /// Как поймём, что получилось: проверяемые признаки.
    var successCriteria: [String]

    // Модель состояния (ADR-036): где человек относительно цели.
    /// Стадии этой цели по порядку. Свои у каждой цели: у запуска
    /// приложения — «Исследование → Разработка → … → Рост», у личного
    /// бренда — другие. Предлагает Linea, человек правит.
    var stages: [String]
    /// Текущая крупная стадия; nil — не выбрана.
    var stage: String?
    /// Крупные этапы — для прогресса по этапам.
    var milestones: [GoalMilestone]
    /// Числа цели — для прогресса по числу.
    var metrics: [GoalMetric]
    /// Как считать прогресс. Выбирает Linea при создании, человек меняет.
    var progressMethod: GoalProgressMethod
    /// Где цель по словам человека (`manual`). nil у целей, созданных со
    /// слайдером: тогда состояние следует из прежнего `progress`.
    var manualState: GoalManualState?
    /// Чья цель (`scope`): моя, команды, компании. По умолчанию — своя.
    var scope: GoalScope {
        didSet { if scope.isShared { sharedScope = scope } }
    }
    /// Какой общей цель была — команды или компании. Остаётся, когда человек
    /// выбирает «От меня», как своя часть и свои числа: вернул «От команды» —
    /// цель снова компании, а не просто команды. nil — общей она не была.
    var sharedScope: GoalScope?
    /// За какую часть общей цели отвечает сам человек (`owner_scope`):
    /// «Новые enterprise-клиенты и ключевые переговоры». Шаги Linea строит
    /// только в этих рамках (`GoalStepScope`). У своей цели — nil.
    var ownerScope: String?
    /// Свои числа у командной цели — вклад человека
    /// (`personal_contribution_progress`): «2 из 5 enterprise-клиентов».
    /// Общий прогресс — в `metrics`; одно другого не определяет.
    var contributionMetrics: [GoalMetric]
    /// Тип, который выбрал человек; nil — как решит Linea (`GoalClassifier`).
    var kindOverride: GoalKind?
    /// Продвижения человека: этапы, числа, стадии (`GoalRevision`).
    var progressLog: [GoalProgressEvent]
    /// Когда человек последний раз пересматривал цель: создал, сохранил
    /// карточку, сдвинул прогресс. nil — цель сохранена раньше, чем Linea
    /// стала это помнить.
    var lastReviewedAt: Date?
    /// «Пока нет» на «Хочешь найти для неё небольшое окно завтра?»: до этого
    /// момента Linea о цели не напоминает (`GoalAttention`).
    var attentionSnoozedUntil: Date?

    init(
        id: UUID = UUID(),
        title: String,
        progress: Double = 0,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        startDate: Date? = nil,
        endDate: Date? = nil,
        isActive: Bool = true,
        priority: TaskPriority = .normal,
        details: String? = nil,
        currentState: String? = nil,
        targetState: String? = nil,
        successCriteria: [String] = [],
        stages: [String] = [],
        stage: String? = nil,
        milestones: [GoalMilestone] = [],
        metrics: [GoalMetric] = [],
        progressMethod: GoalProgressMethod = .manual,
        manualState: GoalManualState? = nil,
        scope: GoalScope = .personal,
        ownerScope: String? = nil,
        contributionMetrics: [GoalMetric] = [],
        kindOverride: GoalKind? = nil,
        progressLog: [GoalProgressEvent] = [],
        sharedScope: GoalScope? = nil,
        lastReviewedAt: Date? = nil,
        attentionSnoozedUntil: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.progress = min(max(progress, 0), 1)
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.startDate = startDate ?? createdAt
        self.endDate = endDate
        self.isActive = isActive
        self.priority = priority
        self.details = details
        self.currentState = currentState
        self.targetState = targetState
        self.successCriteria = successCriteria
        self.stages = stages
        self.stage = stage
        self.milestones = milestones
        self.metrics = metrics
        self.progressMethod = progressMethod
        self.manualState = manualState
        self.scope = scope
        self.sharedScope = scope.isShared ? scope : sharedScope.flatMap { $0.isShared ? $0 : nil }
        self.ownerScope = ownerScope
        self.contributionMetrics = contributionMetrics
        self.kindOverride = kindOverride
        self.progressLog = progressLog
        self.lastReviewedAt = lastReviewedAt
        self.attentionSnoozedUntil = attentionSnoozedUntil
    }

    /// Мягкое чтение, как у задачи: цели лежат и в документах дня.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        let storedProgress = try container.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        progress = min(max(storedProgress, 0), 1)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        let created = try container.decode(Date.self, forKey: .createdAt)
        createdAt = created
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate) ?? created
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .normal
        details = try container.decodeIfPresent(String.self, forKey: .details)
        currentState = try container.decodeIfPresent(String.self, forKey: .currentState)
        targetState = try container.decodeIfPresent(String.self, forKey: .targetState)
        successCriteria = try container.decodeIfPresent([String].self, forKey: .successCriteria) ?? []
        // Модель состояния — мягче остального: незнакомое значение из будущей
        // версии не должно стоить человеку цели, а дню — его записи.
        stages = (try? container.decodeIfPresent([String].self, forKey: .stages)) ?? []
        stage = try? container.decodeIfPresent(String.self, forKey: .stage)
        milestones = (try? container.decodeIfPresent([GoalMilestone].self, forKey: .milestones)) ?? []
        metrics = (try? container.decodeIfPresent([GoalMetric].self, forKey: .metrics)) ?? []
        progressMethod = (try? container.decodeIfPresent(GoalProgressMethod.self, forKey: .progressMethod)) ?? .manual
        manualState = try? container.decodeIfPresent(GoalManualState.self, forKey: .manualState)
        var scope = (try? container.decodeIfPresent(GoalScope.self, forKey: .scope)) ?? .personal
        // `owner_scope` — текст. Сборка раунда 7 хранила под этим ключом «чья
        // цель» («personal», «team», «shared»): это не зона ответственности.
        let owner = try? container.decodeIfPresent(String.self, forKey: .ownerScope)
        if let legacy = GoalScope.legacy(owner) {
            if scope == .personal { scope = legacy }
            ownerScope = nil
        } else {
            ownerScope = owner
        }
        self.scope = scope
        // Записано раньше, чем Linea стала это помнить, — какой общей цель
        // была, знает только сама «чья цель».
        let shared = try? container.decodeIfPresent(GoalScope.self, forKey: .sharedScope)
        sharedScope = scope.isShared ? scope : shared.flatMap { $0.isShared ? $0 : nil }
        contributionMetrics = (try? container.decodeIfPresent([GoalMetric].self, forKey: .contributionMetrics)) ?? []
        kindOverride = try? container.decodeIfPresent(GoalKind.self, forKey: .kindOverride)
        progressLog = (try? container.decodeIfPresent([GoalProgressEvent].self, forKey: .progressLog)) ?? []
        lastReviewedAt = try? container.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        attentionSnoozedUntil = try? container.decodeIfPresent(Date.self, forKey: .attentionSnoozedUntil)
    }

    /// «Низкая / Средняя / Высокая» — важность цели в женском роде.
    static func importanceTitle(_ priority: TaskPriority) -> String {
        switch priority {
        case .low: return "Низкая"
        case .normal: return "Средняя"
        case .important: return "Высокая"
        }
    }

    /// Сколько дней осталось до срока; `nil`, если срок не задан.
    func daysLeft(from moment: Date, calendar: Calendar) -> Int? {
        guard let endDate else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: moment),
                                           to: calendar.startOfDay(for: endDate)).day ?? 0
        return max(0, days)
    }

    /// Срок прошёл, а цель не закрыта.
    func isOverdue(at moment: Date, calendar: Calendar) -> Bool {
        guard let endDate, !isCompleted else { return false }
        return calendar.startOfDay(for: endDate) < calendar.startOfDay(for: moment)
    }

    /// Soft limit from the brief: 1–3 active goals.
    static let recommendedActiveLimit = 3

    /// Где цель по словам человека: выбранное состояние, а у цели, созданной
    /// со слайдером, — из прежнего прогресса.
    var reportedState: GoalManualState {
        manualState ?? GoalManualState.from(legacyProgress: progress)
    }

    /// Следующий незакрытый этап — «следующий рубеж».
    var nextMilestone: GoalMilestone? {
        milestones.first { !$0.isDone }
    }

    /// «Эта цель зависит только от тебя или от команды?»: «От меня» — своя;
    /// «От команды» — снова такая общая, какой была (команды или компании),
    /// а впервые — команды.
    mutating func setShared(_ isShared: Bool) {
        if !isShared {
            scope = .personal
        } else if !scope.isShared {
            scope = sharedScope ?? .team
        }
    }

    /// Часть человека в общей цели — если цель общая и часть названа.
    var ownPart: String? {
        guard scope.isShared, let ownerScope else { return nil }
        let trimmed = ownerScope.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A dated (or undated) group of tasks used to lay out the Plan screen,
/// e.g. "Сб · Сегодня" or "Без дня".
nonisolated struct TaskSection: Identifiable, Sendable {
    let id: String
    let day: Date?
    var tasks: [LineaTask]
}

/// The scope toggle on the Plan screen.
nonisolated enum PlanScope: Int, CaseIterable, Sendable {
    case week = 0
    case month = 1
}
