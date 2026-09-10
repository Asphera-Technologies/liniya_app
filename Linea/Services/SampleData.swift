//
//  SampleData.swift
//  Linea
//
//  ⚠️ SAMPLE DATA — now down to the last screen that has no real source.
//
//  Tasks, goals, health, the day plan, nutrition and the profile are all real.
//  What remains is only the Linea AI greeting and its starter prompts, which
//  become real once the assistant answers from the plan.
//

import Foundation

enum SampleData {

    // MARK: Linea AI (sample: free-form assistant not integrated yet)

    static let aiGreeting = "Я Linea. Вижу твой день, здоровье и планы. Что нужно?"

    static let aiSuggestions: [String] = [
        "Составь план на сегодня",
        "Как мой сон на этой неделе?",
        "Что приготовить на обед?"
    ]
}
