//
//  LanguageModelClient.swift
//  Linea
//
//  Транспорт к облачной модели. Намеренно провайдер-независимый: адрес,
//  путь и модель — настройки, а не константы в коде. Сегодня это Grok от
//  xAI, завтра может быть что угодно с тем же форматом.
//
//  Разбор ответа принимает обе формы, которые сейчас в ходу:
//    • `choices[0].message.content` — совместимый с OpenAI /chat/completions;
//    • `output_text` / `output[].content[].text` — новый /responses у xAI.
//  Так смена эндпоинта в настройках не требует правки кода.
//
//  Ключ сюда приходит снаружи (`AISettings`) и никогда не лежит в репозитории.
//

import Foundation

nonisolated struct LanguageModelConfiguration: Sendable, Equatable {
    var baseURL: URL
    /// Путь запроса относительно базового адреса.
    var path: String
    var model: String
    var apiKey: String
    var timeout: TimeInterval
    /// Верхняя граница ответа, чтобы случайный длинный вывод не съел трафик.
    var maxOutputTokens: Int?

    init(
        baseURL: URL,
        path: String = "chat/completions",
        model: String,
        apiKey: String,
        timeout: TimeInterval = 30,
        maxOutputTokens: Int? = 600
    ) {
        self.baseURL = baseURL
        self.path = path
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
        self.maxOutputTokens = maxOutputTokens
    }

    var endpoint: URL { baseURL.appending(path: path) }

    /// Новый стиль xAI: сообщения лежат в `input`, а не в `messages`.
    var usesResponsesAPI: Bool { path.contains("responses") }
}

nonisolated enum LanguageModelError: Error, LocalizedError {
    case notConfigured
    case http(status: Int, body: String)
    case emptyAnswer
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Ключ доступа к модели не настроен."
        case .http(let status, _): return "Модель ответила ошибкой \(status)."
        case .emptyAnswer: return "Модель вернула пустой ответ."
        case .transport(let message): return message
        }
    }
}

nonisolated struct LanguageModelClient: Sendable {
    let configuration: LanguageModelConfiguration
    private let session: URLSession

    init(configuration: LanguageModelConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// Один запрос: системная инструкция плюс вопрос пользователя.
    func complete(system: String, user: String) async throws -> String {
        guard !configuration.apiKey.isEmpty else { throw LanguageModelError.notConfigured }

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        let messages: [[String: String]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": user],
        ]
        var body: [String: Any] = ["model": configuration.model]
        body[configuration.usesResponsesAPI ? "input" : "messages"] = messages
        if let maxOutputTokens = configuration.maxOutputTokens {
            body[configuration.usesResponsesAPI ? "max_output_tokens" : "max_tokens"] = maxOutputTokens
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LanguageModelError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LanguageModelError.http(status: http.statusCode, body: String(decoding: data.prefix(400), as: UTF8.self))
        }

        guard let text = Self.text(from: data), !text.isEmpty else {
            throw LanguageModelError.emptyAnswer
        }
        return text
    }

    /// Достаёт текст, не завися от того, какой из двух форматов пришёл.
    static func text(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // /chat/completions
        if let choices = root["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // /responses, короткая форма
        if let text = root["output_text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // /responses, полная форма
        if let output = root["output"] as? [[String: Any]] {
            let parts = output.flatMap { item -> [String] in
                guard let content = item["content"] as? [[String: Any]] else { return [] }
                return content.compactMap { $0["text"] as? String }
            }
            let joined = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }

        return nil
    }
}
