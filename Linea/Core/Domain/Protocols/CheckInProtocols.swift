//
//  CheckInProtocols.swift
//  Linea
//
//  Границы итога дня: кто превращает голос в текст, кто разбирает текст и
//  где хранятся дневник и память. Ядро знает только эти протоколы — какой
//  распознаватель и какой разбор стоят за ними, решает `AppContainer`.
//  Всё работает на телефоне: наружу итог дня не уходит (ADR-021).
//

import Foundation

/// Распознанный рассказ и кто его распознал.
nonisolated struct Transcript: Sendable, Equatable {
    let text: String
    /// `local:<модель>` или `apple`.
    let transcriberID: String
    /// Почему не сработал основной распознаватель, если текст дал запасной.
    var fallbackReason: String?

    init(text: String, transcriberID: String, fallbackReason: String? = nil) {
        self.text = text
        self.transcriberID = transcriberID
        self.fallbackReason = fallbackReason
    }
}

/// Голос → текст. Реализации: модель GigaAM и системная диктовка — обе на
/// телефоне (`Linea/Data/Speech`).
nonisolated protocol SpeechTranscribing: Sendable {
    /// Для журнала: `local:<модель>` или `apple`.
    var id: String { get }
    /// Распознаёт записанный файл целиком. `localeIdentifier` — `ru_RU`.
    func transcribe(audioAt url: URL, localeIdentifier: String) async throws -> Transcript
}

/// Текст рассказа → что сделано, сколько работал, как день, что запомнить.
nonisolated protocol CheckInExtracting: Sendable {
    var id: String { get }
    func extract(_ request: CheckInRequest) async throws -> CheckInExtraction
}

/// Дневник: одна запись на день. Как и остальные репозитории, привязан к
/// главному актору — там живёт `mainContext` SwiftData.
protocol CheckInRepository {
    func entry(for day: Date) async throws -> CheckInEntry?
    /// Записи с `day >= since`, от старых к новым.
    func entries(since: Date) async throws -> [CheckInEntry]
    func save(_ entry: CheckInEntry) async throws
    func delete(day: Date) async throws
    func deleteAll() async throws
}

/// Долговременная память — один документ.
protocol MemoryRepository {
    func load() async throws -> UserMemory
    func save(_ memory: UserMemory) async throws
}
