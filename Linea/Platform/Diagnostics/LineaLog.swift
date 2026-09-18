//
//  LineaLog.swift
//  Linea
//
//  Единая точка логирования. До этого приложение молчало: если что-то не
//  работало на чужом телефоне, узнать причину было неоткуда.
//
//  Пишем в системный журнал, поэтому логи видны в Console на Mac и читаются
//  самим приложением на экране «Диагностика» — даже когда Mac рядом нет.
//
//  Про приватность: система по умолчанию прячет подставленные значения как
//  `<private>`. Числа, нужные для отладки (длительности, количества, статусы),
//  помечаем открытыми явно. Сырые замеры здоровья, тексты задач и ключ модели
//  в журнал не попадают.
//

import Foundation
import OSLog

nonisolated enum LineaLog {
    static let subsystem = "com.asphera.Linea"

    static let health = Logger(subsystem: subsystem, category: "health")
    static let context = Logger(subsystem: subsystem, category: "context")
    static let plan = Logger(subsystem: subsystem, category: "plan")
    static let nudges = Logger(subsystem: subsystem, category: "nudges")
    static let ai = Logger(subsystem: subsystem, category: "ai")
    static let nutrition = Logger(subsystem: subsystem, category: "nutrition")
    static let storage = Logger(subsystem: subsystem, category: "storage")

    /// Окружение, с которого полезно начинать любой разбор: версия системы и
    /// сборки. Половина вопросов «почему у него не работает» отсюда и решается.
    static func environment() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let build = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "iOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion), сборка \(build)"
    }
}
