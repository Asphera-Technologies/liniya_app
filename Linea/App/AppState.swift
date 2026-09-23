//
//  AppState.swift
//  Linea
//
//  Lightweight app-wide UI state, injected via the environment. Kept small
//  on purpose — this is not a place for business logic, just cross-cutting
//  presentation state such as the ambient Linea AI surface.
//

import Observation

@Observable
@MainActor
final class AppState {

    /// Whether the Linea AI sheet is presented (driven by the command bar).
    var isPresentingAI = false

    /// Text the user typed into a command bar before opening AI, if any.
    var pendingPrompt: String = ""

    /// Opens the ambient Linea AI surface, optionally seeded with a prompt.
    func openAI(prompt: String = "") {
        pendingPrompt = prompt
        isPresentingAI = true
    }

    /// Whether the «Итог дня» sheet is presented (Today card, evening notification).
    var isPresentingCheckIn = false

    /// Opens the evening check-in: tell how the day went by voice or text.
    func openCheckIn() {
        isPresentingAI = false
        isPresentingCheckIn = true
    }
}
