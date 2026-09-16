//
//  VkusVillClient.swift
//  Linea
//
//  Каталог ВкусВилла через их официальный MCP-эндпоинт.
//
//  Проверено вживую (16.09.2026): `POST https://mcp001.vkusvill.ru/mcp`,
//  JSON-RPC 2.0, без авторизации. Ответ приходит конвертом MCP —
//  `result.content[0].text` содержит JSON строкой, внутри либо
//  `{"ok": true, "data": {"meta": …, "items": […]}}`, либо
//  `{"ok": false, "error": {"code", "message", …}}`.
//
//  Из восьми инструментов нам нужны два: поиск товара и сборка ссылки на
//  корзину. Важное ограничение: истории заказов в API нет и аккаунт
//  пользователя недоступен. Поэтому «что человек съел» узнаётся не постфактум,
//  а в момент, когда корзину собирает само приложение.
//
//  Запросы жёстко лимитируются на стороне ВкусВилла: поиск отвечает
//  `rate_limited` даже на редких запросах. Отсюда пауза между запросами и
//  небольшой потолок позиций.
//

import Foundation

nonisolated struct VkusVillProduct: Sendable, Identifiable, Hashable {
    let id: Int
    /// Идентификатор для корзины — именно его ждёт `cart_link_create`.
    let xmlID: Int
    let title: String
    let price: Double?
    /// Килокалории на 100 г, если каталог их отдал.
    let kilocalories: Double?
    let composition: String?
}

nonisolated enum VkusVillError: Error, LocalizedError {
    case rateLimited
    case service(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .rateLimited: return "ВкусВилл ограничил частоту запросов, попробуй позже."
        case .service(let message): return message
        case .badResponse: return "Не разобрал ответ ВкусВилла."
        }
    }
}

nonisolated struct VkusVillClient: Sendable {
    /// Официальный MCP-эндпоинт ВкусВилла.
    static let defaultEndpoint = URL(string: "https://mcp001.vkusvill.ru/mcp")!
    /// Пауза между запросами: каталог отвечает `rate_limited` на частые.
    static let pauseBetweenRequests = Duration.milliseconds(700)
    /// Больше 20 позиций корзина всё равно не принимает.
    static let maximumCartItems = 20

    let endpoint: URL
    private let session: URLSession

    init(endpoint: URL = VkusVillClient.defaultEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    // MARK: - Инструменты

    /// Первый подходящий товар по названию.
    func firstProduct(matching query: String) async throws -> VkusVillProduct? {
        let data = try await call(
            tool: "vkusvill_products_search",
            arguments: ["q": query, "page": 1, "mode": "short", "sort": "popularity"]
        )
        let items = (data["items"] as? [[String: Any]]) ?? []
        return items.lazy.compactMap(Self.product).first
    }

    /// Ссылка на корзину с уже набранными товарами.
    func cartLink(items: [(xmlID: Int, quantity: Double)]) async throws -> URL? {
        let products = items.prefix(Self.maximumCartItems).map { item in
            ["xml_id": item.xmlID, "q": item.quantity] as [String: Any]
        }
        guard !products.isEmpty else { return nil }
        let data = try await call(tool: "vkusvill_cart_link_create", arguments: ["products": products])
        // Ссылка приходит либо строкой, либо внутри items — принимаем обе формы.
        if let link = Self.link(in: data) { return URL(string: link) }
        return nil
    }

    // MARK: - Транспорт

    /// Один вызов инструмента. Разворачивает конверт MCP и возвращает `data`.
    private func call(tool: String, arguments: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": ["name": tool, "arguments": arguments],
        ])

        let (data, _) = try await session.data(for: request)
        guard let payload = Self.unwrap(data) else { throw VkusVillError.badResponse }

        if (payload["ok"] as? Bool) == false {
            let code = payload["code"] as? String
            if code == "rate_limited" { throw VkusVillError.rateLimited }
            let message = (payload["error"] as? [String: Any])?["message"] as? String
            throw VkusVillError.service(message ?? "ВкусВилл вернул ошибку.")
        }
        return (payload["data"] as? [String: Any]) ?? [:]
    }

    /// `result.content[0].text` — JSON строкой внутри конверта MCP.
    static func unwrap(_ data: Data) -> [String: Any]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let result = root["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String,
              let inner = text.data(using: .utf8)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: inner) as? [String: Any]
    }

    /// Каталог называет поля по-разному в разных инструментах, поэтому берём
    /// первое подходящее имя, а не одно жёстко заданное.
    static func product(_ item: [String: Any]) -> VkusVillProduct? {
        guard let xmlID = number(item, "xml_id").map({ Int($0) }), xmlID > 0 else { return nil }
        let id = number(item, "id").map { Int($0) } ?? xmlID
        guard let title = string(item, "name", "title", "product_name") else { return nil }
        return VkusVillProduct(
            id: id,
            xmlID: xmlID,
            title: title,
            price: number(item, "price", "price_now", "cost"),
            kilocalories: number(item, "kcal", "calories", "energy"),
            composition: string(item, "composition", "ingredients", "structure")
        )
    }

    static func link(in data: [String: Any]) -> String? {
        if let link = string(data, "link", "url", "cart_link") { return link }
        if let items = data["items"] as? [[String: Any]] {
            return items.compactMap { string($0, "link", "url", "cart_link") }.first
        }
        return nil
    }

    private static func string(_ item: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            if let value = item[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private static func number(_ item: [String: Any], _ keys: String...) -> Double? {
        for key in keys {
            if let value = item[key] as? Double { return value }
            if let value = item[key] as? Int { return Double(value) }
            if let value = item[key] as? String, let parsed = Double(value) { return parsed }
        }
        return nil
    }
}
