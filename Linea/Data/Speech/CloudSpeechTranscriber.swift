//
//  CloudSpeechTranscriber.swift
//  Linea
//
//  Облачное распознавание речи. По умолчанию — xAI `POST /v1/stt`, модель
//  `grok-voice-transcribe-2.0`: русский поддерживается, ключ тот же, что у
//  чата, цена $0.10 за час записи — пятиминутный итог дня стоит меньше цента.
//  Проверено вживую 23.09.2026: 21 секунда русской речи распознаётся за
//  полторы секунды со знаками препинания.
//
//  Клиент провайдер-независимый, как `LanguageModelClient`: путь
//  `audio/transcriptions` включает формат OpenAI (OpenAI, Groq), любой
//  другой — формат xAI. Ответ у обоих — `{"text": …}`.
//

import Foundation

nonisolated struct SpeechServiceConfiguration: Sendable, Equatable {
    var baseURL: URL
    var path: String
    var model: String
    var apiKey: String
    var timeout: TimeInterval

    init(baseURL: URL, path: String, model: String, apiKey: String, timeout: TimeInterval = 90) {
        self.baseURL = baseURL
        self.path = path
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
    }

    var endpoint: URL { baseURL.appending(path: path) }

    /// OpenAI-совместимый эндпоинт вместо xAI.
    var isOpenAIStyle: Bool { path.contains("audio/transcriptions") }
}

nonisolated enum SpeechServiceError: Error, LocalizedError {
    case notConfigured
    case unreadableFile
    case http(status: Int, body: String)
    case emptyTranscript
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Ключ доступа к распознаванию не настроен."
        case .unreadableFile: return "Не удалось прочитать запись."
        case .http(let status, _): return "Сервис распознавания ответил ошибкой \(status)."
        case .emptyTranscript: return "В записи не распознано ни слова."
        case .transport(let message): return message
        }
    }
}

nonisolated struct CloudSpeechTranscriber: SpeechTranscribing {
    let configuration: SpeechServiceConfiguration
    /// Слова, которые распознаватель должен узнавать: названия задач,
    /// «Linea», «КП». Без подсказки «Linea» превращается в «линия».
    let keyterms: [String]
    private let session: URLSession

    init(configuration: SpeechServiceConfiguration, keyterms: [String] = [], session: URLSession = .shared) {
        self.configuration = configuration
        self.keyterms = keyterms
        self.session = session
    }

    var id: String { "cloud:\(configuration.model)" }

    func transcribe(audioAt url: URL, localeIdentifier: String) async throws -> Transcript {
        guard !configuration.apiKey.isEmpty else { throw SpeechServiceError.notConfigured }
        let audio: Data
        do {
            audio = try Data(contentsOf: url)
        } catch {
            throw SpeechServiceError.unreadableFile
        }

        let language = String(localeIdentifier.prefix(2)).lowercased()
        var fields: [(String, String)] = [("model", configuration.model), ("language", language)]
        if configuration.isOpenAIStyle {
            fields.append(("response_format", "json"))
        } else {
            // Числа цифрами: «минут на 40» — так их понимает разбор длительностей.
            fields.append(("format", "true"))
            for term in Self.normalizedKeyterms(keyterms) { fields.append(("keyterm", term)) }
        }

        let boundary = "Linea-\(UUID().uuidString)"
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipart(fields: fields, fileName: url.lastPathComponent, mimeType: "audio/mp4", file: audio, boundary: boundary)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SpeechServiceError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SpeechServiceError.http(status: http.statusCode, body: String(decoding: data.prefix(400), as: UTF8.self))
        }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = (root["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { throw SpeechServiceError.emptyTranscript }
        return Transcript(text: text, transcriberID: id)
    }

    /// xAI принимает до ста подсказок по 50 символов.
    static func normalizedKeyterms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(100)
            .map { String($0.prefix(50)) }
    }

    /// Поля формы, файл — последним: xAI требует именно такой порядок.
    static func multipart(fields: [(String, String)], fileName: String, mimeType: String, file: Data, boundary: String) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(file)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}
