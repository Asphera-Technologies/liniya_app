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
    case morning, nudge, evening, taskDeferred
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

    init(moment: ExplanationMoment, facts: [Fact], taskTitles: [String] = [], localeIdentifier: String = "ru_RU", hour: Int, userName: String? = nil) {
        self.moment = moment
        self.facts = facts
        self.taskTitles = taskTitles
        self.localeIdentifier = localeIdentifier
        self.hour = hour
        self.userName = userName
    }
}

nonisolated struct Explanation: Codable, Hashable, Sendable {
    /// One calm opening line («Доброе утро. Сегодня нагрузку лучше немного снизить.»).
    let headline: String
    /// 1–3 sentences of what to do and why.
    let body: String
    let explainerID: String

    var text: String { body.isEmpty ? headline : "\(headline) \(body)" }
}

nonisolated protocol Explainer: Sendable {
    var id: String { get }
    func explain(_ request: ExplanationRequest) async throws -> Explanation
}
