//
//  RemoteExplainer.swift
//  Linea
//
//  Облачная модель переписывает уже принятое решение человеческим языком.
//  Она не меняет план и не выбирает приоритеты — их считает ядро.
//
//  Ответ проходит `ExplanationValidator` в `FallbackExplainer`: числа только
//  из фактов, слово «обычно» только при наличии личной нормы, без медицины.
//  Не прошёл — пользователь видит шаблонный текст и ничего не теряет.
//

import Foundation

nonisolated struct RemoteExplainer: Explainer {
    let id: String
    private let client: LanguageModelClient

    init(client: LanguageModelClient, id: String = "cloud") {
        self.client = client
        self.id = id
    }

    static let systemPrompt = """
    Ты Linea — спокойный личный ассистент. Перепиши сообщение по-русски, на «ты», \
    двумя-тремя короткими предложениями. Используй только факты из блока «Факты»: \
    не добавляй чисел, которых там нет, и не придумывай причин. Не давай медицинских \
    советов. Не меняй порядок задач и не предлагай другой план — он уже составлен.
    """

    func explain(_ request: ExplanationRequest) async throws -> Explanation {
        let base = RuleBasedExplainer().render(request)
        let user = """
        Факты:
        \(base.reasons.isEmpty ? "—" : base.reasons.joined(separator: "\n"))

        Сообщение: \(base.headline) \(base.body)

        Задачи, которые можно называть: \(request.taskTitles.isEmpty ? "—" : request.taskTitles.joined(separator: ", "))
        """
        let text = try await client.complete(system: Self.systemPrompt, user: user)
        return Explanation(headline: base.headline, body: text, reasons: base.reasons, explainerID: id)
    }
}
