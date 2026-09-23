//
//  CheckIn.swift
//  Linea
//
//  «Итог дня» — вечерний чек-ин голосом или текстом. Человек за пару минут
//  рассказывает, что сделал, сколько работал и как прошёл день; Linea
//  разбирает рассказ, показывает, что поняла, и после подтверждения отмечает
//  задачи, записывает оценку дня и пополняет память.
//
//  Здесь три стадии одного рассказа:
//    • `CheckInExtraction` — что предложил разборщик (правила или модель);
//    • `CheckInDraft` — то, что человек видит и правит на экране проверки;
//    • `CheckInEntry` — подтверждённый итог, который хранится в дневнике.
//  Решения о задачах и калибровке принимает код, модель только читает текст.
//

import Foundation

// MARK: - Источник

nonisolated enum CheckInSource: Codable, Hashable, Sendable {
    /// Голос; длительность записи в секундах.
    case voice(seconds: Int)
    case text

    var isVoice: Bool {
        if case .voice = self { return true }
        return false
    }
}

// MARK: - Что понял разборщик

nonisolated enum TaskOutcomeStatus: String, Codable, Hashable, Sendable {
    case done
    case partial
    case notDone

    var title: String {
        switch self {
        case .done: return "сделано"
        case .partial: return "частично"
        case .notDone: return "не сделано"
        }
    }
}

/// Судьба одной задачи из рассказа. `isConfident == false` — задача упомянута,
/// но из слов не ясно, сделана ли она: такую строку экран не отмечает сам.
nonisolated struct TaskOutcome: Codable, Hashable, Sendable {
    let taskID: UUID
    var status: TaskOutcomeStatus
    var isConfident: Bool

    init(taskID: UUID, status: TaskOutcomeStatus, isConfident: Bool = true) {
        self.taskID = taskID
        self.status = status
        self.isConfident = isConfident
    }
}

/// Сделанное, чего не было в списке задач: «ещё созвонился с поставщиком».
nonisolated struct ExtraWork: Codable, Hashable, Sendable {
    var title: String
    var minutes: Int?

    init(title: String, minutes: Int? = nil) {
        self.title = title
        self.minutes = minutes
    }
}

/// Как человек сам оценивает свои силы — не путать с энергией State Engine.
nonisolated enum SelfReportedEnergy: String, Codable, Hashable, Sendable, CaseIterable {
    case low, medium, high

    var title: String {
        switch self {
        case .low: return "мало сил"
        case .medium: return "силы есть"
        case .high: return "много сил"
        }
    }
}

nonisolated struct CheckInExtraction: Codable, Hashable, Sendable {
    var outcomes: [TaskOutcome]
    var extra: [ExtraWork]
    /// Сколько всего работал — только если человек это сказал.
    var statedWorkMinutes: Int?
    var rating: DayRating?
    var energy: SelfReportedEnergy?
    /// Одно предложение от модели; у правил его нет.
    var summary: String?
    var memory: [MemoryCandidate]
    /// Кто разбирал: `rules` или идентификатор модели.
    var extractorID: String

    init(
        outcomes: [TaskOutcome] = [],
        extra: [ExtraWork] = [],
        statedWorkMinutes: Int? = nil,
        rating: DayRating? = nil,
        energy: SelfReportedEnergy? = nil,
        summary: String? = nil,
        memory: [MemoryCandidate] = [],
        extractorID: String
    ) {
        self.outcomes = outcomes
        self.extra = extra
        self.statedWorkMinutes = statedWorkMinutes
        self.rating = rating
        self.energy = energy
        self.summary = summary
        self.memory = memory
        self.extractorID = extractorID
    }

    func outcome(for taskID: UUID) -> TaskOutcome? {
        outcomes.first { $0.taskID == taskID }
    }
}

/// Всё, что нужно разборщику: текст, задачи дня и то, что Linea уже знает.
nonisolated struct CheckInRequest: Sendable {
    let transcript: String
    let day: Date
    /// Задачи, о которых человек мог рассказать (см. `relevantTasks`).
    let tasks: [LineaTask]
    /// Уже известные факты — чтобы модель не предлагала их повторно.
    let knownFacts: [String]
    let time: TimeContext

    init(transcript: String, day: Date, tasks: [LineaTask], knownFacts: [String] = [], time: TimeContext) {
        self.transcript = transcript
        self.day = day
        self.tasks = tasks
        self.knownFacts = knownFacts
        self.time = time
    }

    /// Задачи, о которых вечером имеет смысл спрашивать: всё запланированное
    /// на этот день, просроченное, закрытое сегодня и немного задач без дня.
    /// Порядок стабильный — по нему модели выдаются номера задач.
    static func relevantTasks(from tasks: [LineaTask], day: Date, time: TimeContext, limit: Int = 30) -> [LineaTask] {
        let dayStart = time.startOfDay(day)
        let dayInterval = time.dayInterval(containing: dayStart)

        func order(_ lhs: LineaTask, _ rhs: LineaTask) -> Bool {
            lhs.createdAt != rhs.createdAt ? lhs.createdAt < rhs.createdAt : lhs.id.uuidString < rhs.id.uuidString
        }

        let planned = tasks.filter { task in
            guard let date = task.date else { return false }
            return time.isSameDay(date, dayStart)
        }.sorted(by: order)

        let closedThatDay = tasks.filter { task in
            guard task.isDone, let completedAt = task.completedAt else { return false }
            return dayInterval.contains(completedAt) && !planned.contains(task)
        }.sorted(by: order)

        let overdue = tasks.filter { task in
            guard !task.isDone, let date = task.date else { return false }
            return time.startOfDay(date) < dayStart
        }.sorted(by: order)

        let undated = tasks.filter { $0.date == nil && !$0.isDone }
            .sorted { lhs, rhs in lhs.createdAt != rhs.createdAt ? lhs.createdAt > rhs.createdAt : lhs.id.uuidString < rhs.id.uuidString }
            .prefix(10)

        var seen = Set<UUID>()
        var result: [LineaTask] = []
        for task in planned + closedThatDay + overdue + Array(undated) where seen.insert(task.id).inserted {
            result.append(task)
        }
        return Array(result.prefix(limit))
    }
}

// MARK: - Подтверждённый итог

/// Задача в итоге дня. Название копируется: задачу могут удалить, а дневник
/// должен читаться и через месяц.
nonisolated struct ReportedTask: Codable, Hashable, Sendable {
    let taskID: UUID?
    let title: String
    let minutes: Int?
    var status: TaskOutcomeStatus
}

nonisolated struct CheckInReport: Codable, Hashable, Sendable {
    var completed: [ReportedTask]
    var unfinished: [ReportedTask]
    var extra: [ExtraWork]
    var statedWorkMinutes: Int?
    var rating: DayRating?
    var energy: SelfReportedEnergy?
    var summary: String?
    /// Сколько задач было назначено на этот день.
    var plannedCount: Int
    /// Сколько из назначенных закрыто.
    var completedPlannedCount: Int
    var movedToTomorrow: [UUID]

    init(
        completed: [ReportedTask] = [],
        unfinished: [ReportedTask] = [],
        extra: [ExtraWork] = [],
        statedWorkMinutes: Int? = nil,
        rating: DayRating? = nil,
        energy: SelfReportedEnergy? = nil,
        summary: String? = nil,
        plannedCount: Int = 0,
        completedPlannedCount: Int = 0,
        movedToTomorrow: [UUID] = []
    ) {
        self.completed = completed
        self.unfinished = unfinished
        self.extra = extra
        self.statedWorkMinutes = statedWorkMinutes
        self.rating = rating
        self.energy = energy
        self.summary = summary
        self.plannedCount = plannedCount
        self.completedPlannedCount = completedPlannedCount
        self.movedToTomorrow = movedToTomorrow
    }

    /// Объём работы: со слов человека, а если он не сказал — по оценкам
    /// закрытых задач и того, что он назвал сверху.
    var workMinutes: Int? {
        if let statedWorkMinutes { return statedWorkMinutes }
        let estimated = completed.compactMap(\.minutes).reduce(0, +) + extra.compactMap(\.minutes).reduce(0, +)
        return estimated > 0 ? estimated : nil
    }

    var isWorkStated: Bool { statedWorkMinutes != nil }
}

/// Запись дневника. Одна на день: повторный чек-ин заменяет предыдущий.
nonisolated struct CheckInEntry: Codable, Hashable, Sendable, Identifiable {
    static let schemaVersion = 1

    let id: UUID
    let day: Date
    let createdAt: Date
    var updatedAt: Date
    var source: CheckInSource
    /// Сырой рассказ. Хранится только на телефоне; через `compactionDays`
    /// дней стирается, остаются итог и выжимка.
    var transcript: String?
    var report: CheckInReport
    /// Короткая строка для контекста модели: «22.09, пн: сделано 3 из 5…».
    var digest: String
    var extractorID: String

    init(
        id: UUID,
        day: Date,
        createdAt: Date,
        updatedAt: Date,
        source: CheckInSource,
        transcript: String?,
        report: CheckInReport,
        digest: String,
        extractorID: String
    ) {
        self.id = id
        self.day = day
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source
        self.transcript = transcript
        self.report = report
        self.digest = digest
        self.extractorID = extractorID
    }

    /// Мягкое чтение, как у профиля: дневник живёт долго, и новая сборка
    /// не должна терять записи, сделанные старой.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        day = try container.decode(Date.self, forKey: .day)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? day
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        source = try container.decodeIfPresent(CheckInSource.self, forKey: .source) ?? .text
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        report = try container.decodeIfPresent(CheckInReport.self, forKey: .report) ?? CheckInReport()
        digest = try container.decodeIfPresent(String.self, forKey: .digest) ?? ""
        extractorID = try container.decodeIfPresent(String.self, forKey: .extractorID) ?? "rules"
    }

    /// Сколько дней хранится сырой рассказ.
    static let compactionDays = 60

    /// Старые записи сжимаются: сырой текст уходит, итог и выжимка остаются.
    /// Это аналог компакции в OpenClaw — история не растёт бесконечно, а в
    /// контекст модели всё равно попадает только выжимка.
    func compacted(asOf time: TimeContext) -> CheckInEntry {
        guard transcript != nil, time.days(from: day, to: time.today) > Self.compactionDays else { return self }
        var copy = self
        copy.transcript = nil
        return copy
    }
}

/// Итог дня в форме, которую понимает Feedback Engine: план против факта.
nonisolated struct DayReportSummary: Codable, Hashable, Sendable {
    let plannedTasks: Int
    let completedPlannedTasks: Int
    /// Минуты рабочих блоков плана и сколько из них пришлось на закрытые задачи.
    let plannedMinutes: Int
    let completedPlannedMinutes: Int
    let workMinutes: Int?

    init(plannedTasks: Int, completedPlannedTasks: Int, plannedMinutes: Int, completedPlannedMinutes: Int, workMinutes: Int?) {
        self.plannedTasks = plannedTasks
        self.completedPlannedTasks = completedPlannedTasks
        self.plannedMinutes = plannedMinutes
        self.completedPlannedMinutes = completedPlannedMinutes
        self.workMinutes = workMinutes
    }

    /// Какая доля плана случилась на самом деле; `nil`, если плана не было.
    var completionRatio: Double? {
        if plannedMinutes > 0 { return Double(completedPlannedMinutes) / Double(plannedMinutes) }
        if plannedTasks > 0 { return Double(completedPlannedTasks) / Double(plannedTasks) }
        return nil
    }
}
