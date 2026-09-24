//
//  CheckInPrompt.swift
//  Linea
//
//  Запрос к модели для разбора итога дня и чтение её ответа. Живёт в ядре,
//  потому что это чистая логика: какой текст уходит наружу и как понимается
//  ответ — проверяется тестами без сети и без телефона.
//
//  Экономия токенов заложена в форму запроса:
//    • задачи идут под номерами, а не под UUID — модель не выдумывает
//      идентификаторы, а номер стоит один токен вместо двадцати;
//    • из памяти уходит только короткий список уже известных фактов;
//    • сырой рассказ отправляется один раз — дальше в запросах живёт выжимка.
//

import Foundation

nonisolated struct CheckInPrompt: Sendable {

    static let systemPrompt = """
    Ты разбираешь вечерний рассказ человека о прошедшем дне для приложения-планировщика. \
    Ответь только JSON-объектом, без пояснений и без markdown:
    {"done":[],"partial":[],"not_done":[],"mentioned":[],"extra":[{"title":"","minutes":null}],\
    "work_minutes":null,"rating":null,"energy":null,"summary":"","remember":[{"text":"","kind":"pattern"}]}
    Правила:
    - done, partial, not_done, mentioned — только номера из списка «Задачи». done — сказал, что сделал, провёл, \
    закрыл, даже если с трудом или дольше плана («затянулся», «еле успел»). partial — сам сказал, что начал, \
    но не закончил. not_done — не успел, перенёс, отменил. mentioned — упомянул, но непонятно, сделал ли. \
    Сомневаешься — mentioned. Не упомянул — никуда не пиши.
    - extra — сделанное, чего нет в списке: 2–5 слов. minutes — только если он назвал время.
    - work_minutes — сколько всего работал за день, только если он назвал общее время. Время на отдельное \
    дело — не общий объём. Иначе null.
    - rating: "great" — день понравился, "ok" — обычный, "hard" — тяжело, устал, не справился. Непонятно — null.
    - energy: "low", "medium" или "high" — как он сам описывает свои силы. Непонятно — null.
    - summary — одно нейтральное предложение до 120 символов о том, как прошёл день. Без советов и без чисел, \
    которых нет в рассказе.
    - remember — до трёх устойчивых фактов о человеке, полезных в будущем: привычки, предпочтения, \
    ограничения, закономерности («после обеда проседает концентрация»). Только то, что он сам сказал о себе, \
    без догадок. kind: "preference", "pattern", "constraint" или "context". Не записывай разовые события дня, \
    подробности о здоровье и то, что есть в «Уже известно». Коротко, от третьего лица. Просьбы «запомни …» \
    записывай обязательно.
    """

    /// Задачи в том порядке, в каком они получили номера.
    let tasks: [LineaTask]

    init(tasks: [LineaTask]) {
        self.tasks = tasks
    }

    // MARK: Запрос

    func user(for request: CheckInRequest, maxFacts: Int = 12) -> String {
        var lines: [String] = []
        lines.append("Задачи:")
        if tasks.isEmpty {
            lines.append("— нет")
        } else {
            for (index, task) in tasks.enumerated() {
                lines.append("\(index + 1). \(task.title)\(details(of: task, request: request))")
            }
        }

        let facts = request.knownFacts.prefix(maxFacts)
        if !facts.isEmpty {
            lines.append("")
            lines.append("Уже известно:")
            lines.append(contentsOf: facts.map { "- \($0)" })
        }

        lines.append("")
        lines.append("Рассказ:")
        lines.append("«\(request.transcript.trimmingCharacters(in: .whitespacesAndNewlines))»")
        return lines.joined(separator: "\n")
    }

    private func details(of task: LineaTask, request: CheckInRequest) -> String {
        var parts: [String] = []
        if task.isDone { parts.append("уже закрыта") }
        if let date = task.date, request.time.startOfDay(date) < request.time.startOfDay(request.day) {
            parts.append("просрочена")
        } else if task.date == nil {
            parts.append("без дня")
        }
        return parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
    }

    // MARK: Ответ

    nonisolated enum DecodingError: Error, Equatable {
        case noJSON
        case malformed
    }

    /// Читает ответ модели терпимо: JSON может прийти в ```-блоке, номера —
    /// строками, оценка — по-русски. Неизвестные номера отбрасываются.
    func decode(_ text: String, extractorID: String) throws -> CheckInExtraction {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            throw DecodingError.noJSON
        }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw DecodingError.malformed
        }

        // При противоречии верим осторожному: «не сделал» сильнее «сделал».
        var statuses: [Int: (TaskOutcomeStatus, Bool)] = [:]
        let lists: [(keys: [String], status: TaskOutcomeStatus, confident: Bool)] = [
            (["mentioned"], .done, false),
            (["done"], .done, true),
            (["partial"], .partial, true),
            (["not_done", "notDone", "not-done"], .notDone, true),
        ]
        for list in lists {
            for number in list.keys.flatMap({ Self.numbers(root[$0]) }) {
                statuses[number] = (list.status, list.confident)
            }
        }
        let outcomes = tasks.enumerated().compactMap { index, task -> TaskOutcome? in
            guard let (status, confident) = statuses[index + 1] else { return nil }
            return TaskOutcome(taskID: task.id, status: status, isConfident: confident)
        }

        let extra = (root["extra"] as? [Any] ?? []).compactMap { item -> ExtraWork? in
            if let title = item as? String { return ExtraWork(title: title) }
            guard let object = item as? [String: Any], let title = object["title"] as? String else { return nil }
            return ExtraWork(title: title, minutes: Self.integer(object["minutes"]))
        }

        let memory = (root["remember"] as? [Any] ?? []).compactMap { item -> MemoryCandidate? in
            if let text = item as? String { return MemoryCandidate(text: text, kind: MemoryCommand.kind(of: text)) }
            guard let object = item as? [String: Any], let text = object["text"] as? String else { return nil }
            let kind = (object["kind"] as? String).flatMap(MemoryFactKind.init(rawValue:)) ?? MemoryCommand.kind(of: text)
            return MemoryCandidate(text: text, kind: kind)
        }

        return CheckInExtraction(
            outcomes: outcomes,
            extra: extra,
            statedWorkMinutes: Self.integer(root["work_minutes"]),
            rating: Self.rating(root["rating"]),
            energy: Self.energy(root["energy"]),
            summary: (root["summary"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            memory: memory,
            extractorID: extractorID
        )
    }

    // MARK: Терпимое чтение значений

    static func numbers(_ value: Any?) -> [Int] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap(integer)
    }

    static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as Int: return number
        // `Int(exactly:)`: число больше `Int.max` из ответа модели — не повод падать.
        case let number as Double: return Int(exactly: number.rounded())
        case let text as String:
            let digits = text.filter(\.isNumber)
            return digits.isEmpty ? nil : Int(digits)
        default: return nil
        }
    }

    static func rating(_ value: Any?) -> DayRating? {
        guard let text = (value as? String).map(RussianWords.normalized) else { return nil }
        if let rating = DayRating(rawValue: text) { return rating }
        if text.hasPrefix("отлич") || text.hasPrefix("хорош") { return .great }
        if text.hasPrefix("норм") || text.hasPrefix("обыч") { return .ok }
        if text.hasPrefix("тяж") || text.hasPrefix("плох") { return .hard }
        return nil
    }

    static func energy(_ value: Any?) -> SelfReportedEnergy? {
        guard let text = (value as? String).map(RussianWords.normalized) else { return nil }
        if let energy = SelfReportedEnergy(rawValue: text) { return energy }
        if text.hasPrefix("низ") || text.hasPrefix("мал") { return .low }
        if text.hasPrefix("сред") { return .medium }
        if text.hasPrefix("выс") || text.hasPrefix("мног") { return .high }
        return nil
    }
}
