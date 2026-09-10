//
//  RuleBasedExplainer.swift
//  Linea
//
//  Turns typed facts into the Russian the user reads. This is the source of
//  truth for every string in the product: the brief's sentences are golden
//  tests here, and an LLM may only rephrase what this already said.
//
//  Two rules shape the code:
//  • a number appears in the text only if a fact carries it — nothing is
//    computed here, so the text can never disagree with the plan;
//  • «обычно» is allowed only when a comparison fact exists, because without a
//    personal baseline Linea has no idea what usual means.
//
//  For `.meal`, `ExplanationRequest.taskTitles` carries the allowed products
//  rather than task names — the only place where that field means something
//  else, documented here and at the call site.
//

import Foundation

nonisolated struct RuleBasedExplainer: TextRenderer, Explainer {
    let id = "rule-based"

    init() {}

    func explain(_ request: ExplanationRequest) async throws -> Explanation {
        render(request)
    }

    func render(_ request: ExplanationRequest) -> Explanation {
        let facts = FactReader(facts: request.facts, timeZoneIdentifier: request.timeZoneIdentifier)
        switch request.moment {
        case .morning: return morning(request, facts)
        case .nudge: return nudge(request, facts)
        case .evening: return Explanation(headline: "Как прошёл день?", body: "", explainerID: id)
        case .loadAdjustment:
            return Explanation(headline: loadHeadline(facts) ?? "Сегодня обычный ритм.", body: "", reasons: reasons(facts), explainerID: id)
        case .meal: return meal(request, facts)
        case .taskDeferred: return taskDeferred(facts)
        case .dataSituation: return dataSituation(facts)
        }
    }

    // MARK: Morning

    private func morning(_ request: ExplanationRequest, _ facts: FactReader) -> Explanation {
        var headline = RussianText.greeting(hour: request.hour) + "."
        if let advice = loadHeadline(facts) {
            headline += " " + advice
        }

        var sentences: [String] = []
        if let count = facts.topTaskCount {
            if count == 0 {
                sentences.append("На сегодня задач нет.")
            } else {
                let noun = RussianText.plural(count, "приоритетное действие", "приоритетных действия", "приоритетных действий")
                sentences.append("У тебя есть \(count) \(noun).")
            }
        }
        if let deadline = facts.hardWorkDeadline {
            sentences.append("Самую сложную работу предлагаю сделать до \(facts.clock(deadline)).")
        }

        return Explanation(headline: headline, body: sentences.joined(separator: " "), reasons: reasons(facts), explainerID: id)
    }

    /// The load verdict as a sentence. `.normal` says nothing: a calm day
    /// needs no announcement.
    private func loadHeadline(_ facts: FactReader) -> String? {
        switch facts.loadAdvice {
        case .reduce: return "Сегодня нагрузку лучше немного снизить."
        case .push: return "Сегодня можно взять больше."
        case .normal, .unknown, nil: return nil
        }
    }

    // MARK: Nudge

    private func nudge(_ request: ExplanationRequest, _ facts: FactReader) -> Explanation {
        guard let behind = facts.behindSchedule else {
            return Explanation(headline: "План немного отстаёт.", body: "", explainerID: id)
        }
        var sentences: [String] = []
        if let next = facts.nextCommitment {
            sentences.append("До следующего обязательства осталось \(RussianText.duration(minutes: next.minutesLeft)).")
        } else if let minutesLeft = facts.endOfWorkdayMinutes {
            sentences.append("До конца рабочего дня осталось \(RussianText.duration(minutes: minutesLeft)).")
        }
        sentences.append("Закрываем \(RussianText.quoted(behind.title)) сейчас или переносим?")
        return Explanation(headline: "План немного отстаёт.", body: sentences.joined(separator: " "), explainerID: id)
    }

    // MARK: Meal

    private func meal(_ request: ExplanationRequest, _ facts: FactReader) -> Explanation {
        if let workout = facts.workoutPlanned {
            return Explanation(
                headline: "Перед тренировкой в \(facts.clock(workout)) стоит перекусить.",
                body: products(request),
                explainerID: id
            )
        }
        guard let window = facts.mealWindow else {
            return Explanation(headline: "Не забудь поесть.", body: products(request), explainerID: id)
        }
        let lighter = facts.loadAdvice == .reduce
        let headline = lighter
            ? "\(window.kind.title) в \(facts.clock(window.start)) лучше сделать полегче."
            : "\(window.kind.title) в \(facts.clock(window.start))."
        return Explanation(headline: headline, body: products(request), explainerID: id)
    }

    /// For `.meal` the request's `taskTitles` carries allowed products.
    private func products(_ request: ExplanationRequest) -> String {
        let list = request.taskTitles.prefix(3)
        guard !list.isEmpty else { return "" }
        return "Например: \(list.joined(separator: ", "))."
    }

    // MARK: Deferred / data

    private func taskDeferred(_ facts: FactReader) -> Explanation {
        guard let deferred = facts.taskDeferred else {
            return Explanation(headline: "Задачу переносим.", body: "", explainerID: id)
        }
        return Explanation(
            headline: "\(RussianText.quoted(deferred.title)) переносим.",
            body: deferred.reason,
            explainerID: id
        )
    }

    private func dataSituation(_ facts: FactReader) -> Explanation {
        if let coldStart = facts.coldStart {
            return Explanation(
                headline: "Пока мало данных.",
                body: "",
                reasons: ["Собираю базу: день \(coldStart.days) из \(coldStart.needed) — сравнивать с обычным пока рано."],
                explainerID: id
            )
        }
        return Explanation(
            headline: "Не вижу данных Apple Health.",
            body: "",
            reasons: ["Не вижу данных о сне — планирую по времени и приоритетам."],
            explainerID: id
        )
    }

    // MARK: Reasons

    /// Why Linea says what it says: sleep, recovery, and the data situation.
    /// Every line is backed by a fact — there is no line without evidence.
    private func reasons(_ facts: FactReader) -> [String] {
        var lines: [String] = []

        if let sleep = facts.sleepDuration {
            if let vsUsual = facts.sleepVsUsual, vsUsual.level != .unknown {
                let magnitude = RussianText.duration(minutes: Int((abs(vsUsual.deltaSeconds) / 60).rounded()))
                let direction = vsUsual.deltaSeconds < 0 ? "меньше" : "больше"
                lines.append("Сон \(RussianText.hoursMinutes(seconds: sleep)) — на \(magnitude) \(direction) обычного.")
            } else if let coldStart = facts.coldStart {
                lines.append("Сон \(RussianText.hoursMinutes(seconds: sleep)).")
                lines.append("Собираю базу: день \(coldStart.days) из \(coldStart.needed) — сравнивать с обычным пока рано.")
            } else {
                lines.append("Сон \(RussianText.hoursMinutes(seconds: sleep)).")
            }
        } else if facts.hasMissingSleep {
            lines.append("Не вижу данных о сне — планирую по времени и приоритетам.")
        } else if let coldStart = facts.coldStart {
            lines.append("Собираю базу: день \(coldStart.days) из \(coldStart.needed) — сравнивать с обычным пока рано.")
        }

        switch facts.recoveryLevel {
        case .belowUsual: lines.append("Восстановление ниже обычного.")
        case .aboveUsual: lines.append("Восстановление лучше обычного.")
        case .usual, .unknown, nil: break
        }

        if facts.highLoadYesterday { lines.append("Вчера была заметная нагрузка.") }
        return lines
    }
}

/// Reads the typed facts a renderer needs, so every branch above stays flat.
nonisolated struct FactReader: Sendable {
    let facts: [Fact]
    let timeZoneIdentifier: String

    private var time: TimeContext {
        TimeContext(now: Date(timeIntervalSince1970: 0), timeZoneIdentifier: timeZoneIdentifier)
    }

    func clock(_ date: Date) -> String { RussianText.clock(date, time: time) }

    var loadAdvice: LoadAdvice? {
        for fact in facts { if case .loadAdvice(let advice) = fact { return advice } }
        return nil
    }

    var topTaskCount: Int? {
        for fact in facts { if case .topTaskCount(let count) = fact { return count } }
        return nil
    }

    var hardWorkDeadline: Date? {
        for fact in facts { if case .hardWorkDeadline(let date) = fact { return date } }
        return nil
    }

    var sleepDuration: TimeInterval? {
        for fact in facts { if case .sleepDuration(let seconds) = fact { return seconds } }
        return nil
    }

    var sleepVsUsual: (deltaSeconds: TimeInterval, level: UsualLevel)? {
        for fact in facts { if case .sleepVsUsual(let delta, let level) = fact { return (delta, level) } }
        return nil
    }

    var recoveryLevel: UsualLevel? {
        for fact in facts { if case .recovery(let level) = fact { return level } }
        return nil
    }

    var coldStart: (days: Int, needed: Int)? {
        for fact in facts { if case .coldStart(let days, let needed) = fact { return (days, needed) } }
        return nil
    }

    var hasMissingSleep: Bool {
        facts.contains { if case .dataMissing(let kind) = $0 { return kind == .sleepSegment }; return false }
    }

    var highLoadYesterday: Bool {
        facts.contains { if case .highLoadYesterday = $0 { return true }; return false }
    }

    var behindSchedule: (taskID: UUID, title: String, lagMinutes: Int)? {
        for fact in facts { if case .behindSchedule(let id, let title, let lag) = fact { return (id, title, lag) } }
        return nil
    }

    var nextCommitment: (title: String, at: Date, minutesLeft: Int)? {
        for fact in facts { if case .nextCommitment(let title, let at, let minutes) = fact { return (title, at, minutes) } }
        return nil
    }

    var endOfWorkdayMinutes: Int? {
        for fact in facts { if case .endOfWorkday(let minutes) = fact { return minutes } }
        return nil
    }

    var mealWindow: (kind: MealKind, start: Date, end: Date)? {
        for fact in facts { if case .mealWindow(let kind, let start, let end) = fact { return (kind, start, end) } }
        return nil
    }

    var workoutPlanned: Date? {
        for fact in facts { if case .workoutPlanned(let at) = fact { return at } }
        return nil
    }

    var taskDeferred: (taskID: UUID, title: String, reason: String)? {
        for fact in facts { if case .taskDeferred(let id, let title, let reason) = fact { return (id, title, reason) } }
        return nil
    }

    var dietRestrictions: Int? {
        for fact in facts { if case .dietRestrictions(let count) = fact { return count } }
        return nil
    }
}
