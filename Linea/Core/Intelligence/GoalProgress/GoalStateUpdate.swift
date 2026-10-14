//
//  GoalStateUpdate.swift
//  Linea
//
//  «Обновить состояние» цели (ADR-047): человек одним действием рассказывает,
//  что изменилось, — текстом или голосом:
//
//      «TestFlight уже сделали, onboarding почти готов, но аналитику пока не
//       подключали.»
//
//  Linea сначала показывает, как поняла, и ничего не меняет до «Подтвердить»:
//
//      Обновлю состояние
//      ✓ TestFlight — завершено
//      ● Onboarding — почти готов
//      ○ Аналитика — не начата
//      Новый фокус: закончить onboarding и подключить аналитику.
//
//  Разбор — правилами на телефоне, как остальное: фраза делится на части
//  (запятые, «но», «а»), в каждой — признак состояния («уже сделали»,
//  «почти», «не подключали») и то, о чём речь. Это узнаётся среди этапов цели
//  по основам слов; незнакомое — новый этап. Числа цели («уже 18
//  пользователей») и стадия («идёт тестирование») — тоже. После «Подтвердить»
//  меняются этапы, числа, стадия, «Что уже сделано» и ближайшие шаги;
//  прежнее «Что уже сделано» уходит в историю, закрытые этапы — в журнал
//  продвижений (`GoalRevision`), план пересчитывается.
//

import Foundation

nonisolated struct GoalStateUpdate: Hashable, Sendable {
    nonisolated enum Status: String, Hashable, Sendable {
        case done
        case almostDone
        case inProgress
        case notStarted

        var mark: String {
            switch self {
            case .done: return "✓"
            case .almostDone, .inProgress: return "●"
            case .notStarted: return "○"
            }
        }
    }

    /// Этап или то, о чём сказали.
    nonisolated struct Item: Hashable, Sendable, Identifiable {
        /// «Аналитика» — как будет называться этап.
        let title: String
        let status: Status
        /// Знакомый этап цели; nil — новый.
        let milestoneID: UUID?
        /// Как сказано — для шага: «подключить аналитику».
        let said: String
        /// Глагол шага, если его можно взять из сказанного: «подключить».
        let verb: String?

        var id: String { title }
    }

    nonisolated struct MetricChange: Hashable, Sendable {
        let metricID: UUID
        let unit: String
        let from: Double
        let to: Double
    }

    /// Что сказал человек — станет «Что уже сделано».
    let text: String
    let items: [Item]
    let metrics: [MetricChange]
    /// Новая стадия, если о ней сказано.
    let stage: String?
    /// Ближайшие шаги: «Закончить onboarding», «Подключить аналитику».
    let focus: [String]

    /// Понять ничего не удалось — предлагать нечего.
    var isEmpty: Bool { items.isEmpty && metrics.isEmpty && stage == nil }

    /// «✓ TestFlight — завершено», «● Onboarding — почти готов», «○ Аналитика — не начата».
    static func line(_ item: Item) -> String {
        "\(item.status.mark) \(item.title) — \(statusText(item.status, for: item.title))"
    }

    /// «Новый фокус: закончить onboarding и подключить аналитику.»
    var focusSentence: String? { Self.focusSentence(focus) }

    /// Ближайшие шаги одной фразой — и в предложении, и в карточке цели.
    static func focusSentence(_ focus: [String]) -> String? {
        guard !focus.isEmpty else { return nil }
        let steps = focus.map { $0.prefix(1).lowercased() + $0.dropFirst() }
        let joined = steps.count == 1 ? steps[0]
            : steps.dropLast().joined(separator: ", ") + " и " + steps[steps.count - 1]
        return "Новый фокус: \(joined)."
    }

    /// Состояние в роде названия: «почти готов», «почти готова», «почти готово».
    static func statusText(_ status: Status, for title: String) -> String {
        let gender = Self.gender(of: title)
        switch status {
        case .done: return "завершено"
        case .inProgress: return "в процессе"
        case .almostDone: return ["почти готов", "почти готова", "почти готово"][gender]
        case .notStarted: return ["не начат", "не начата", "не начато"][gender]
        }
    }

    /// 0 — мужской (и латиница), 1 — женский, 2 — средний — по окончанию
    /// первого слова.
    private static func gender(of title: String) -> Int {
        guard let first = RussianWords.tokens(title).first?.normalized, let last = first.last else { return 0 }
        if "ая".contains(last) { return 1 }
        if "оеё".contains(last) { return 2 }
        return 0
    }
}

nonisolated struct GoalUpdateReader: Sendable {
    init() {}

    // MARK: Понять

    func read(_ text: String, goal: LineaGoal) -> GoalStateUpdate {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [GoalStateUpdate.Item] = []
        var stage: (index: Int, title: String)?
        // «Уже 18 пользователей» — число цели, а не этап «Пользователей».
        let unitStems = Set(GoalMetricReader.metrics(in: said).flatMap { RussianWords.stems($0.unit) })
        let currentStage = goal.stage.flatMap { goal.stages.firstIndex(of: $0) } ?? -1

        for clause in Self.clauses(said) {
            let words = RussianWords.tokens(clause).filter { !$0.isNumber }
            guard let status = Self.status(of: words.map(\.normalized)) else { continue }

            // Стадия: «идёт тестирование» — она; «тестирование закончили» —
            // следующая за ней.
            if status != .notStarted, let found = Self.stage(in: words.map(\.normalized), stages: goal.stages) {
                let index = status == .done ? min(found + 1, goal.stages.count - 1) : found
                if index > currentStage, index > (stage?.index ?? -1) { stage = (index, goal.stages[index]) }
            }

            // О чём речь: всё, кроме признаков состояния и служебных слов; «X и Y» — два.
            let verb = Self.verb(in: words.map(\.normalized))
            for phrase in Self.subjects(words) where !phrase.isEmpty {
                let stems = Set(phrase.map(\.normalized).filter { $0.count >= 3 }.map(RussianWords.stem))
                if !stems.isEmpty, stems.isSubset(of: unitStems) { continue }
                let original = phrase.map(\.original).joined(separator: " ")
                let milestone = Self.milestone(for: phrase.map(\.normalized), in: goal.milestones)
                // Об этапе, который совпал со стадией, этапом не говорим.
                if milestone == nil, Self.stage(in: phrase.map(\.normalized), stages: goal.stages) != nil { continue }
                let title = milestone?.title ?? Self.title(from: phrase)
                guard !items.contains(where: { $0.title.lowercased() == title.lowercased() }) else { continue }
                items.append(GoalStateUpdate.Item(title: title, status: status, milestoneID: milestone?.id,
                                                  said: original, verb: verb))
            }
        }

        let metrics = Self.metricChanges(in: said, goal: goal)
        let focus = items.compactMap { item -> String? in
            switch item.status {
            case .almostDone, .inProgress: return "Закончить \(item.said)"
            case .notStarted: return item.verb.map { "\(RussianWords.capitalizedFirst($0)) \(item.said)" } ?? "Начать «\(item.title)»"
            case .done: return nil
            }
        }
        return GoalStateUpdate(text: said, items: items, metrics: metrics, stage: stage?.title, focus: focus)
    }

    // MARK: Применить

    /// Цель после «Подтвердить». Закрытые этапы не открываются снова: путь
    /// вперёд; прежнее «Что уже сделано» — в историю.
    func applied(_ update: GoalStateUpdate, to goal: LineaGoal, at moment: Date) -> LineaGoal {
        var result = goal
        var added = false
        for item in update.items {
            if let id = item.milestoneID, let index = result.milestones.firstIndex(where: { $0.id == id }) {
                guard !result.milestones[index].isDone else { continue }
                switch item.status {
                case .done:
                    result.milestones[index].completedAt = moment
                    result.milestones[index].state = nil
                case .almostDone: result.milestones[index].state = .almostDone
                case .inProgress: result.milestones[index].state = .inProgress
                case .notStarted: result.milestones[index].state = nil
                }
            } else {
                added = true
                result.milestones.append(GoalMilestone(
                    id: UUID(), title: item.title,
                    completedAt: item.status == .done ? moment : nil,
                    state: item.status == .almostDone ? .almostDone : item.status == .inProgress ? .inProgress : nil
                ))
            }
        }
        // Появились этапы — прогресс их показывает: у числа — «этапы и
        // числа», у «отмечаю сам» и «без процентов» — этапы.
        if added {
            switch result.progressMethod {
            case .metric: result.progressMethod = .hybrid
            case .manual, .qualitative: result.progressMethod = .milestones
            case .milestones, .hybrid: break
            }
        }
        for change in update.metrics {
            if let index = result.metrics.firstIndex(where: { $0.id == change.metricID }) {
                result.metrics[index].current = change.to
            } else if let index = result.contributionMetrics.firstIndex(where: { $0.id == change.metricID }) {
                result.contributionMetrics[index].current = change.to
            }
        }
        if let stage = update.stage { result.stage = stage }
        if !update.text.isEmpty {
            if let previous = goal.currentState?.trimmingCharacters(in: .whitespacesAndNewlines),
               !previous.isEmpty, previous != update.text {
                result.stateHistory.append(GoalStateNote(at: moment, text: previous))
            }
            result.currentState = update.text
        }
        result.nextActions = update.focus
        return result
    }

    // MARK: Слова

    /// Части фразы: «TestFlight уже сделали» · «onboarding почти готов» ·
    /// «аналитику пока не подключали».
    static func clauses(_ text: String) -> [String] {
        let separated = text.replacingOccurrences(of: "[.,;!?\n]", with: "|", options: .regularExpression)
            .replacingOccurrences(of: "(?i)\\s(но|а|однако|зато)\\s", with: "|", options: .regularExpression)
        return separated.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Признак состояния части; nil — о состоянии ничего не сказано.
    static func status(of words: [String]) -> GoalStateUpdate.Status? {
        if words.contains("не") { return .notStarted }
        if words.contains(where: { word in almostWords.contains { word.hasPrefix($0) } }) { return .almostDone }
        if words.contains(where: { word in progressWords.contains { word.hasPrefix($0) } }) { return .inProgress }
        if words.contains("уже") || words.contains(where: { word in doneWords.contains { word.hasPrefix($0) } }) {
            return .done
        }
        return nil
    }

    static let almostWords = ["почти", "доделыва", "заканчива", "финиш"]
    static let progressWords = ["процесс", "делаем", "делаю", "делает", "делают", "занимаем", "занимаюс", "работаем",
                                "работаю", "начали", "начал", "идет", "идут", "пилим", "работе", "готовим",
                                "готовлю", "готовит"]
    static let doneWords = ["готов", "сделал", "сделан", "законч", "заверш", "запустил", "запущен", "выпустил",
                            "выпущен", "подключил", "подключен", "настроил", "настроен", "сдали", "сдал", "прошл",
                            "прошли", "отправил", "залил", "опубликова", "собрал", "внедрил", "интегрировал",
                            "добавил", "реализова", "написал", "есть"]
    /// Служебное — не то, о чём речь.
    static let fillers: Set<String> = ["уже", "пока", "еще", "не", "почти", "в", "мы", "я", "у", "нас", "наш", "наша",
                                       "наше", "наши", "тоже", "также", "вот", "так", "же", "совсем", "полностью",
                                       "вообще", "только", "сейчас", "все", "всё", "его", "ее", "её", "их", "это",
                                       "по", "с", "со", "над", "на", "ещё", "был", "была", "было", "были"]

    /// Глагол для шага из сказанного: «не подключали» → «подключить».
    static func verb(in words: [String]) -> String? {
        for word in words {
            if let infinitive = infinitives.first(where: { word.hasPrefix($0.key) })?.value { return infinitive }
        }
        return nil
    }

    static let infinitives: [String: String] = [
        "подключа": "подключить", "настраива": "настроить", "делал": "сделать", "начинал": "начать",
        "запуска": "запустить", "писал": "написать", "тестирова": "протестировать", "собирал": "собрать",
        "интегрирова": "интегрировать", "отправля": "отправить", "готовил": "подготовить", "внедря": "внедрить",
        "добавля": "добавить", "проводил": "провести", "выпуска": "выпустить", "публикова": "опубликовать",
    ]

    /// То, о чём речь в части: слова без признаков состояния и служебных;
    /// «X и Y» — два предмета.
    static func subjects(_ words: [SpokenToken]) -> [[SpokenToken]] {
        let kept = words.filter { word in
            let normalized = word.normalized
            if fillers.contains(normalized) && normalized != "и" { return false }
            let isStatus = almostWords.contains { normalized.hasPrefix($0) }
                || progressWords.contains { normalized.hasPrefix($0) }
                || doneWords.contains { normalized.hasPrefix($0) }
                || infinitives.keys.contains { normalized.hasPrefix($0) }
                || normalized.hasPrefix("подключал") || normalized.hasPrefix("начат")
            return !isStatus
        }
        var result: [[SpokenToken]] = [[]]
        for word in kept {
            if word.normalized == "и" {
                if !(result.last?.isEmpty ?? true) { result.append([]) }
            } else {
                result[result.count - 1].append(word)
            }
        }
        return result.filter { !$0.isEmpty }
    }

    /// Этап цели, о котором речь: больше всего общих основ.
    static func milestone(for words: [String], in milestones: [GoalMilestone]) -> GoalMilestone? {
        let said = Set(words.filter { $0.count >= 3 }.map(RussianWords.stem))
        guard !said.isEmpty else { return nil }
        let scored = milestones.compactMap { milestone -> (GoalMilestone, Int)? in
            let common = said.intersection(RussianWords.stems(milestone.title)).count
            return common > 0 ? (milestone, common) : nil
        }
        return scored.max { lhs, rhs in lhs.1 < rhs.1 }?.0
    }

    /// Стадия цели, названная в словах.
    static func stage(in words: [String], stages: [String]) -> Int? {
        let said = Set(words.filter { $0.count >= 3 }.map(RussianWords.stem))
        return stages.indices.last { index in !said.intersection(RussianWords.stems(stages[index])).isEmpty }
    }

    /// Название нового этапа: «аналитику» → «Аналитика», «onboarding» → «Onboarding».
    static func title(from phrase: [SpokenToken]) -> String {
        let words = phrase.map { token -> String in
            let word = token.original
            let lower = word.lowercased()
            guard lower.range(of: "^[а-яё]+$", options: .regularExpression) != nil, lower.count > 3 else { return word }
            if lower.hasSuffix("ию") { return String(word.dropLast(2)) + "ия" }
            if lower.hasSuffix("у"), let before = lower.dropLast().last, !"аеёиоуыэюя".contains(before) {
                return String(word.dropLast()) + "а"
            }
            return word
        }
        return RussianWords.capitalizedFirst(words.joined(separator: " "))
    }

    /// Числа цели в словах: «уже 18 пользователей» — «Сейчас» у числа «пользователей».
    static func metricChanges(in text: String, goal: LineaGoal) -> [GoalStateUpdate.MetricChange] {
        let all = goal.metrics + goal.contributionMetrics
        return GoalMetricReader.metrics(in: text).compactMap { found in
            let stems = RussianWords.stems(found.unit)
            guard let metric = all.first(where: { !stems.intersection(RussianWords.stems($0.unit)).isEmpty || $0.unit == found.unit }),
                  metric.current != found.target else { return nil }
            return GoalStateUpdate.MetricChange(metricID: metric.id, unit: metric.unit, from: metric.current, to: found.target)
        }
    }
}
