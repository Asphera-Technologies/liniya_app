//
//  Memory.swift
//  Linea
//
//  Долговременная память о человеке — то, что в OpenClaw лежит в MEMORY.md:
//  короткий курируемый список устойчивых фактов («после обеда проседаю»,
//  «по вторникам зал в 19:00»). Не дневник и не переписка: дневник — это
//  `CheckInEntry`, а сюда попадает только то, что пригодится через неделю.
//
//  Список ограничен по размеру, и это главное его свойство: сколько бы дней
//  ни прошло, в запрос к модели уходит не больше нескольких сотен токенов.
//

import Foundation

nonisolated enum MemoryFactKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// Что человеку нравится и как ему удобнее.
    case preference
    /// Повторяющаяся закономерность: «после обеда проседаю».
    case pattern
    /// Ограничение: «после 20:00 не работаю».
    case constraint
    /// Обстоятельства жизни: «готовлюсь к марафону».
    case context

    var title: String {
        switch self {
        case .preference: return "Предпочтение"
        case .pattern: return "Закономерность"
        case .constraint: return "Ограничение"
        case .context: return "Контекст"
        }
    }
}

/// Предложение что-то запомнить — от правил («запомни, что…») или модели.
/// Фактом оно становится только после `MemoryConsolidator`.
nonisolated struct MemoryCandidate: Codable, Hashable, Sendable {
    var text: String
    var kind: MemoryFactKind
    /// Человек сам попросил запомнить. Такой факт закрепляется.
    var isExplicit: Bool

    init(text: String, kind: MemoryFactKind = .context, isExplicit: Bool = false) {
        self.text = text
        self.kind = kind
        self.isExplicit = isExplicit
    }
}

nonisolated enum MemorySource: Codable, Hashable, Sendable {
    /// Из итога дня за этот день.
    case checkIn(day: Date)
    /// Из разговора: «запомни, что…».
    case chat
    /// Человек записал сам в «Памяти».
    case manual
}

nonisolated struct MemoryFact: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var text: String
    var kind: MemoryFactKind
    var source: MemorySource
    let createdAt: Date
    /// Когда факт последний раз всплывал снова.
    var lastConfirmedAt: Date
    /// Сколько раз всплывал. Один раз и давно — кандидат на забывание.
    var confirmations: Int
    /// Закреплённые факты не вытесняются и не забываются. Всё, что человек
    /// сказал явно («запомни») или записал сам, закрепляется.
    var isPinned: Bool

    init(
        id: UUID,
        text: String,
        kind: MemoryFactKind,
        source: MemorySource,
        createdAt: Date,
        lastConfirmedAt: Date? = nil,
        confirmations: Int = 1,
        isPinned: Bool = false
    ) {
        self.id = id
        self.text = text
        self.kind = kind
        self.source = source
        self.createdAt = createdAt
        self.lastConfirmedAt = lastConfirmedAt ?? createdAt
        self.confirmations = max(1, confirmations)
        self.isPinned = isPinned
    }

    /// Мягкое чтение: память живёт дольше любой сборки приложения.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        kind = try container.decodeIfPresent(MemoryFactKind.self, forKey: .kind) ?? .context
        source = try container.decodeIfPresent(MemorySource.self, forKey: .source) ?? .manual
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastConfirmedAt = try container.decodeIfPresent(Date.self, forKey: .lastConfirmedAt) ?? createdAt
        confirmations = max(1, try container.decodeIfPresent(Int.self, forKey: .confirmations) ?? 1)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

nonisolated struct UserMemory: Codable, Hashable, Sendable {
    static let schemaVersion = 1

    var facts: [MemoryFact]
    var updatedAt: Date?

    init(facts: [MemoryFact] = [], updatedAt: Date? = nil) {
        self.facts = facts
        self.updatedAt = updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        facts = try container.decodeIfPresent([MemoryFact].self, forKey: .facts) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    static let empty = UserMemory()

    var isEmpty: Bool { facts.isEmpty }
}
