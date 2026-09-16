//
//  AISettings.swift
//  Linea
//
//  Откуда приложение берёт доступ к облачной модели.
//
//  Ключ НЕ лежит в репозитории. Он читается из файла
//  `Linea/Resources/AISecrets.plist`, который добавлен в .gitignore: папка
//  `Linea/` синхронизирована с проектом, поэтому файл попадает в сборку сам,
//  без правок Xcode. Нет файла — приложение просто работает на шаблонах, и
//  сборка на CI не ломается. Как настроить — `Docs/secrets.md`.
//
//  Важно понимать ограничение: ключ, попавший в приложение, извлекается из
//  него кем угодно, у кого есть сборка. Для демо это приемлемо, для магазина
//  нет — там ключ должен жить на сервере, а приложение ходить через него.
//  Точка для такого перехода уже есть: поменять `baseURL` на свой адрес.
//

import Foundation

nonisolated enum AISettings {
    /// Ключи Info.plist, подставляемые из xcconfig.
    private enum PlistKey {
        static let apiKey = "LINEA_AI_API_KEY"
        static let baseURL = "LINEA_AI_BASE_URL"
        static let model = "LINEA_AI_MODEL"
        static let path = "LINEA_AI_PATH"
    }

    /// Значения по умолчанию — Grok от xAI. Меняются без пересборки кода.
    static let defaultBaseURL = "https://api.x.ai/v1"
    static let defaultModel = "grok-4.6"
    static let defaultPath = "chat/completions"

    /// Имя файла с секретами внутри бандла.
    private static let secretsResource = "AISecrets"

    static var apiKey: String {
        value(PlistKey.apiKey) ?? ""
    }

    static var isConfigured: Bool { !apiKey.isEmpty }

    static var configuration: LanguageModelConfiguration? {
        let key = apiKey
        guard !key.isEmpty else { return nil }
        guard let url = URL(string: value(PlistKey.baseURL) ?? defaultBaseURL) else { return nil }
        return LanguageModelConfiguration(
            baseURL: url,
            path: value(PlistKey.path) ?? defaultPath,
            model: value(PlistKey.model) ?? defaultModel,
            apiKey: key
        )
    }

    /// Что показать в «Профиле» → «AI».
    static var statusText: String {
        isConfigured ? "Grok" : "Не настроен"
    }

    /// Сначала файл с секретами, потом Info.plist — на случай, если команда
    /// предпочтёт подставлять значения через xcconfig на сборке.
    private static func value(_ key: String) -> String? {
        if let fromFile = secrets[key] as? String, !fromFile.isEmpty {
            let trimmed = fromFile.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let secrets: [String: Any] = {
        guard let url = Bundle.main.url(forResource: secretsResource, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }()
}
