//
//  DiagnosticsReader.swift
//  Linea
//
//  Читает собственные записи приложения из системного журнала, чтобы их можно
//  было переслать, не подключая телефон к Mac. Ради этого экран «Диагностика»
//  и существует: тестировщик ловит проблему днём, а разбираемся мы потом.
//

import Foundation
import OSLog

nonisolated struct DiagnosticsReader: Sendable {
    /// За какой срок назад собирать записи.
    var window: TimeInterval

    init(window: TimeInterval = 60 * 60) {
        self.window = window
    }

    nonisolated struct Entry: Sendable, Identifiable {
        let id = UUID()
        let date: Date
        let category: String
        let level: String
        let message: String
    }

    /// Записи приложения за последнее время, новые снизу.
    func recentEntries(limit: Int = 500) throws -> [Entry] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let since = store.position(date: Date().addingTimeInterval(-window))
        let predicate = NSPredicate(format: "subsystem == %@", LineaLog.subsystem)

        var entries: [Entry] = []
        for case let entry as OSLogEntryLog in try store.getEntries(at: since, matching: predicate) {
            entries.append(
                Entry(
                    date: entry.date,
                    category: entry.category,
                    level: Self.levelName(entry.level),
                    message: entry.composedMessage
                )
            )
        }
        return Array(entries.suffix(limit))
    }

    /// Готовый текст для пересылки: окружение сверху, дальше записи.
    func report(limit: Int = 500) -> String {
        var lines = ["Linea, диагностика", LineaLog.environment(), ""]
        do {
            let entries = try recentEntries(limit: limit)
            if entries.isEmpty {
                lines.append("Записей нет. Открой экраны, на которых проблема, и вернись сюда.")
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.dateFormat = "HH:mm:ss"
            for entry in entries {
                lines.append("\(formatter.string(from: entry.date)) [\(entry.category)] \(entry.level): \(entry.message)")
            }
        } catch {
            lines.append("Не удалось прочитать журнал: \(error.localizedDescription)")
        }
        return lines.joined(separator: "\n")
    }

    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "ошибка"
        case .fault: return "сбой"
        case .undefined: return "?"
        @unknown default: return "?"
        }
    }
}
