//
//  Explainer.swift
//  Linea
//
//  Turns structured output (facts) into human-friendly Russian text. The
//  rule-based implementation is the source of truth and always available; an
//  LLM implementation (on-device FoundationModels, later a backend proxy) may
//  rephrase but must pass `ExplanationValidator` — no numbers that are not in
//  the facts, no medical advice. LLMs never make decisions.
//

import Foundation

nonisolated enum ExplanationMoment: String, Codable, Sendable {
    /// The morning brief (headline + body).
    case morning
    /// «План немного отстаёт…» — headline = first sentence, body = the rest incl. the question.
    case nudge
    /// «Как прошёл день?»
    case evening
    /// «Сегодня нагрузку лучше немного снизить.» as a standalone recommendation.
    case loadAdjustment
    case taskDeferred
    /// Meal advice from the nutrition rule.
    case meal
    /// «Собираю базу: день N из 7» / «Не вижу данных Apple Health».
    case dataSituation
}

nonisolated struct ExplanationRequest: Codable, Sendable {
    let moment: ExplanationMoment
    let facts: [Fact]
    /// Titles of tasks the text may mention, in plan order.
    let taskTitles: [String]
    let localeIdentifier: String
    /// Hour of day (for the greeting).
    let hour: Int
    let userName: String?
    /// IANA time zone for rendering moments inside facts («до 12:00»).
    let timeZoneIdentifier: String

    init(
        moment: ExplanationMoment,
        facts: [Fact],
        taskTitles: [String] = [],
        localeIdentifier: String = "ru_RU",
        hour: Int,
        userName: String? = nil,
        timeZoneIdentifier: String = "UTC"
    ) {
        self.moment = moment
        self.facts = facts
        self.taskTitles = taskTitles
        self.localeIdentifier = localeIdentifier
        self.hour = hour
        self.userName = userName
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

nonisolated struct Explanation: Codable, Hashable, Sendable {
    /// One calm opening line («Доброе утро. Сегодня нагрузку лучше немного снизить.»).
    let headline: String
    /// 1–3 sentences of what to do and when.
    let body: String
    /// Why Linea says this — shown as a quiet caption under the text, and kept
    /// separate so the headline/body stay exactly the sentences the product
    /// promises while the evidence can grow or disappear with the data.
    let reasons: [String]
    let explainerID: String

    init(headline: String, body: String, reasons: [String] = [], explainerID: String) {
        self.headline = headline
        self.body = body
        self.reasons = reasons
        self.explainerID = explainerID
    }

    var text: String { body.isEmpty ? headline : "\(headline) \(body)" }
}

nonisolated protocol Explainer: Sendable {
    var id: String { get }
    func explain(_ request: ExplanationRequest) async throws -> Explanation
}

/// Synchronous, deterministic text from facts. Engines and rules use it to
/// fill `Recommendation.message` and `Nudge.title/body`; the rule-based
/// explainer conforms to both `TextRenderer` and `Explainer`.
nonisolated protocol TextRenderer: Sendable {
    func render(_ request: ExplanationRequest) -> Explanation
}
