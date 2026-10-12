//
//  GoalModels.swift
//  Linea
//
//  Из чего состоит понимание цели, кроме названия и срока: где человек
//  сейчас (стадия, «Сейчас»), чем измеряется путь (этапы, числа) и как
//  честно показать прогресс (метод). Простые значения — их хранит
//  `LineaGoal`, считает `GoalProgressEngine`, показывает карточка цели.
//
//  Процент — не обязанность цели. «18 из 50 пользователей» — это 36 %;
//  «Развить личный бренд» в процентах не выражается, и Linea его не
//  придумывает (ADR-037).
//

import Foundation

/// Как считать прогресс цели (`progress_method`).
nonisolated enum GoalProgressMethod: String, Codable, CaseIterable, Sendable {
    /// Число: «18 из 50 пользователей» — 36 %.
    case metric
    /// Крупные этапы: ✓ Core loop · ● Onboarding · ○ QA.
    case milestones
    /// Этапы и числа вместе; общего процента нет.
    case hybrid
    /// Человек сам отмечает: начало, в процессе, почти готово, готово.
    case manual
    /// Без процентов: стадия, последнее продвижение, действия за 30 дней.
    case qualitative

    var title: String {
        switch self {
        case .metric: return "Число"
        case .milestones: return "Этапы"
        case .hybrid: return "Этапы и числа"
        case .manual: return "Отмечаю сам"
        case .qualitative: return "Без процентов"
        }
    }

    /// Одна фраза: как Linea будет считать.
    var explanation: String {
        switch self {
        case .metric: return "Прогресс — сколько набрано из цели, например 18 из 50 пользователей."
        case .milestones: return "Прогресс — закрытые крупные этапы. Процент — только если у этапов есть веса."
        case .hybrid: return "Этапы и числа рядом, без общего процента."
        case .manual: return "Ты сам отмечаешь, где цель: начало, в процессе, почти готово, готово."
        case .qualitative: return "Без процентов: стадия, последнее продвижение и значимые действия за 30 дней."
        }
    }
}

/// Где цель, по словам самого человека (`manual`).
nonisolated enum GoalManualState: String, Codable, CaseIterable, Sendable {
    case started
    case inProgress
    case almostDone
    case done

    var title: String {
        switch self {
        case .started: return "Начало"
        case .inProgress: return "В процессе"
        case .almostDone: return "Почти готово"
        case .done: return "Готово"
        }
    }

    /// Насколько цель близка к концу — только для расчёта важности задач
    /// (почти достигнутая цель тянет чуть слабее). На экране — слова.
    var completion: Double {
        switch self {
        case .started: return 0.1
        case .inProgress: return 0.5
        case .almostDone: return 0.85
        case .done: return 1
        }
    }

    /// Цели, созданные со слайдером прогресса: прежнее значение — в слова.
    static func from(legacyProgress progress: Double) -> GoalManualState {
        switch progress {
        case ..<0.25: return .started
        case ..<0.75: return .inProgress
        case ..<1: return .almostDone
        default: return .done
        }
    }
}

/// Измеримая часть цели: «18 из 50 пользователей», «78 кг, цель — 75 кг».
nonisolated struct GoalMetric: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    /// Что считаем — словами человека: «пользователей», «км», «тестировщиков».
    var unit: String
    /// С чего начинали. Обычно 0; у «с 80 до 75 кг» — 80.
    var start: Double
    var current: Double
    var target: Double
    /// Когда человек последний раз поменял текущее значение.
    var updatedAt: Date?

    init(id: UUID, unit: String, start: Double = 0, current: Double? = nil, target: Double, updatedAt: Date? = nil) {
        self.id = id
        self.unit = unit
        self.start = start
        self.current = current ?? start
        self.target = target
        self.updatedAt = updatedAt
    }

    /// Пройденная доля пути от старта к цели, 0…1. Цель совпадает со
    /// стартом — считать не из чего: nil.
    var fraction: Double? {
        let span = target - start
        guard span != 0, span.isFinite, current.isFinite else { return nil }
        return min(max((current - start) / span, 0), 1)
    }

    /// Цель — меньше старта: вес, расходы, время на дистанции.
    var isDecreasing: Bool { target < start }
}

/// Крупный этап цели: «Core loop», «Onboarding», «TestFlight».
nonisolated struct GoalMilestone: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var title: String
    /// Вес этапа, если его задали уверенно. Без весов процента нет — только
    /// «2 из 5 этапов»: Linea не придумывает точность, которой нет.
    var weight: Double?
    var completedAt: Date?

    init(id: UUID, title: String, weight: Double? = nil, completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.weight = weight
        self.completedAt = completedAt
    }

    var isDone: Bool { completedAt != nil }
}

/// Сфера жизни, к которой относится цель (`scope`).
nonisolated enum GoalScope: String, Codable, CaseIterable, Sendable {
    case work
    case health
    case learning
    case finance
    case relationships
    case personal

    var title: String {
        switch self {
        case .work: return "Работа"
        case .health: return "Здоровье"
        case .learning: return "Обучение"
        case .finance: return "Финансы"
        case .relationships: return "Близкие"
        case .personal: return "Личное"
        }
    }
}

/// Чья цель (`owner_scope`): только своя, команды или общая с кем-то.
nonisolated enum GoalOwnerScope: String, Codable, CaseIterable, Sendable {
    case personal
    case team
    case shared

    var title: String {
        switch self {
        case .personal: return "Моя"
        case .team: return "Команды"
        case .shared: return "Общая"
        }
    }
}

/// Тип цели (`goal_type`). Linea определяет его сама (`GoalClassifier`), как
/// тип задачи; от типа — метод прогресса и стадии новой цели. Человек видит
/// тип только тихой строкой в карточке цели и может поправить.
nonisolated enum GoalKind: String, Codable, CaseIterable, Sendable {
    /// Результат, который делается этапами: выпустить, запустить, переехать.
    case project
    /// Измеримый результат: 50 пользователей, 10 км, 300 000 ₽.
    case measurable
    /// Регулярное действие: каждый день, 3 раза в неделю.
    case habit
    /// Научиться: язык, навык, инструмент.
    case skill
    /// Развитие без финиша: личный бренд, увереннее, спокойнее.
    case growth
    /// Ничего из этого Linea не узнала.
    case other

    var title: String {
        switch self {
        case .project: return "Проект"
        case .measurable: return "Измеримая"
        case .habit: return "Привычка"
        case .skill: return "Навык"
        case .growth: return "Развитие"
        case .other: return "Другое"
        }
    }

    /// Как считать прогресс, если в словах нет ни чисел, ни этапов.
    var typicalMethod: GoalProgressMethod {
        switch self {
        case .project: return .milestones
        case .measurable: return .metric
        case .habit, .skill, .growth: return .qualitative
        case .other: return .manual
        }
    }
}

/// Продвижение по цели, которое сделал человек: закрыл этап, обновил число,
/// перешёл на следующую стадию. Только вперёд: откат — не продвижение. Из
/// этого журнала — «последнее продвижение» и «значимые действия за 30 дней».
nonisolated struct GoalProgressEvent: Hashable, Codable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable {
        case milestoneDone
        case metricUpdated
        case stageChanged
        case manualStateChanged
    }

    var kind: Kind
    var at: Date
    /// Этап, стадия, «18 пользователей» — что именно сдвинулось.
    var detail: String?

    init(kind: Kind, at: Date, detail: String? = nil) {
        self.kind = kind
        self.at = at
        self.detail = detail
    }
}
