//
//  RemoteCheckInExtractor.swift
//  Linea
//
//  Разбор итога дня облачной моделью. Промпт и чтение ответа живут в ядре
//  (`CheckInPrompt`) и проверены тестами; здесь только транспорт.
//
//  Ответ проходит `CheckInExtractionValidator` в `FallbackCheckInExtractor`,
//  а при любой ошибке итог дня разбирают правила — человек ничего не теряет.
//

import Foundation

nonisolated struct RemoteCheckInExtractor: CheckInExtracting {
    let client: LanguageModelClient

    init(client: LanguageModelClient) {
        self.client = client
    }

    var id: String { "cloud:\(client.configuration.model)" }

    func extract(_ request: CheckInRequest) async throws -> CheckInExtraction {
        let prompt = CheckInPrompt(tasks: request.tasks)
        let answer = try await client.complete(system: CheckInPrompt.systemPrompt, user: prompt.user(for: request), json: true)
        return try prompt.decode(answer, extractorID: id)
    }
}
