//
//  GoalProgressText.swift
//  Linea
//
//  Прогресс цели по-русски: «18 из 50 пользователей · 36%», «2 из 5
//  этапов», «В процессе», «Разработка · последнее продвижение — вчера».
//  Процент появляется, только когда он есть у `GoalProgress`. Здесь, а не в
//  экране: так строки проверяют тесты, и форматы те же, что у остальных
//  текстов Linea. Числа — без `NumberFormatter`: на Linux и на телефоне
//  строка должна быть одна и та же.
//

import Foundation

nonisolated enum GoalProgressText {
    /// Неразрывный пробел между разрядами: «300 000».
    static let groupSeparator = "\u{00A0}"
    static let separator = " · "

    /// Месяцы в родительном падеже: «до 15 октября».
    static let monthsGenitive = ["января", "февраля", "марта", "апреля", "мая", "июня",
                                 "июля", "августа", "сентября", "октября", "ноября", "декабря"]

    // MARK: Числа

    /// «18», «2,5», «300 000». Дробь — до сотых, без лишних нулей.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let limited = min(abs(value), 1e12)
        var whole = Int(limited.rounded(.down))
        var hundredths = Int(((limited - Double(whole)) * 100).rounded())
        if hundredths == 100 {
            whole += 1
            hundredths = 0
        }
        var text = grouped(whole)
        if hundredths > 0 {
            var digits = String(format: "%02d", hundredths)
            while digits.hasSuffix("0") { digits.removeLast() }
            text += "," + digits
        }
        return (value < 0 && (whole > 0 || hundredths > 0) ? "-" : "") + text
    }

    /// Число, которое человек набрал: «18», «2,5», «300 000». Пусто или не
    /// число — nil.
    static func parseNumber(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: groupSeparator, with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    /// Разряды — от пяти цифр: «1000», но «10 000».
    static func grouped(_ value: Int) -> String {
        let digits = String(value)
        guard digits.count > 4 else { return digits }
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { result += groupSeparator }
            result.append(character)
        }
        return result
    }

    /// «18 пользователей», «2,5 км».
    static func amount(_ value: Double, unit: String) -> String {
        let unit = unit.trimmingCharacters(in: .whitespaces)
        return unit.isEmpty ? number(value) : "\(number(value)) \(unit)"
    }

    /// «18 из 50 пользователей»; цель меньше старта — «78 кг, цель — 75 кг».
    static func metric(_ metric: GoalMetric) -> String {
        if metric.isDecreasing {
            return "\(amount(metric.current, unit: metric.unit)), цель — \(amount(metric.target, unit: metric.unit))"
        }
        return "\(number(metric.current)) из \(amount(metric.target, unit: metric.unit))"
    }

    /// «36%».
    static func percent(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    /// «2 из 5 этапов», «1 из 1 этапа».
    static func milestones(done: Int, total: Int) -> String {
        "\(done) из \(total) \(RussianText.plural(total, "этапа", "этапов", "этапов"))"
    }

    /// «5 значимых действий», «1 значимое действие», «ни одного значимого действия».
    static func actions(_ count: Int) -> String {
        guard count > 0 else { return "ни одного значимого действия" }
        return "\(count) " + RussianText.plural(count, "значимое действие", "значимых действия", "значимых действий")
    }

    // MARK: Даты

    /// «сегодня», «вчера», «3 дня назад», «12 сентября».
    static func moment(_ date: Date, time: TimeContext) -> String {
        let days = time.days(from: date, to: time.now)
        switch days {
        case ...0: return "сегодня"
        case 1: return "вчера"
        case 2...6: return "\(days) \(RussianText.plural(days, "день", "дня", "дней")) назад"
        default: return longDay(date, time: time)
        }
    }

    /// «15 октября», другой год — «15 октября 2027».
    static func longDay(_ date: Date, time: TimeContext) -> String {
        let parts = time.calendar.dateComponents([.day, .month, .year], from: date)
        let month = monthsGenitive[((parts.month ?? 1) - 1 + 12) % 12]
        var text = "\(parts.day ?? 1) \(month)"
        if let year = parts.year, year != time.calendar.component(.year, from: time.now) {
            text += " \(year)"
        }
        return text
    }

    /// Срок цели: «до 15 октября».
    static func deadline(_ date: Date, time: TimeContext) -> String {
        "до " + longDay(date, time: time)
    }

    /// Срок цели коротко — для строки в «Плане»: «до 15 окт».
    static func shortDeadline(_ date: Date, time: TimeContext) -> String {
        "до " + shortDate(date, time: time)
    }

    /// «15 окт»; другой год — «15 окт 2027».
    static func shortDate(_ date: Date, time: TimeContext) -> String {
        let parts = time.calendar.dateComponents([.day, .month, .year], from: date)
        let month = RussianText.monthsShort[((parts.month ?? 1) - 1 + 12) % 12]
        var text = "\(parts.day ?? 1) \(month)"
        if let year = parts.year, year != time.calendar.component(.year, from: time.now) {
            text += " \(year)"
        }
        return text
    }

    // MARK: Целиком

    /// Строка под целью в «Плане»: что известно о прогрессе — и процент,
    /// только если он честный.
    static func summary(_ progress: GoalProgress, time: TimeContext) -> String {
        if progress.isCompleted { return "Выполнено" }
        switch progress.method {
        case .metric:
            // Число без цели (только что добавленное) — ещё не число.
            guard let metric = progress.metrics.first, metric.target != metric.start else { return "Число не задано" }
            return withPercent(self.metric(metric), progress.value)
        case .milestones:
            guard progress.milestonesTotal > 0 else { return "Этапы не заданы" }
            return withPercent(milestones(done: progress.milestonesDone, total: progress.milestonesTotal), progress.value)
        case .hybrid:
            var parts: [String] = []
            if let metric = progress.metrics.first { parts.append(self.metric(metric)) }
            if progress.milestonesTotal > 0 {
                parts.append(milestones(done: progress.milestonesDone, total: progress.milestonesTotal))
            }
            return parts.isEmpty ? "Этапы и числа не заданы" : parts.joined(separator: separator)
        case .manual:
            return (progress.reportedState ?? .started).title
        case .qualitative:
            let last = progress.lastProgressAt.map { "последнее продвижение — \(moment($0, time: time))" }
                ?? "продвижений пока нет"
            guard let stage = progress.stage else { return RussianWords.capitalizedFirst(last) }
            return "\(stage)\(separator)\(last)"
        }
    }

    /// Без процентов: стадия, последнее продвижение, действия за 30 дней.
    static func qualitativeLines(_ progress: GoalProgress, time: TimeContext) -> [(label: String, value: String)] {
        [
            ("Текущая стадия", progress.stage ?? "не выбрана"),
            ("Последнее продвижение", progress.lastProgressAt.map { moment($0, time: time) } ?? "пока не было"),
            ("За \(GoalProgressEngine.recentDays) дней", actions(progress.recentActions)),
        ]
    }

    private static func withPercent(_ text: String, _ value: Double?) -> String {
        guard let value else { return text }
        return "\(text)\(separator)\(percent(value))"
    }
}
