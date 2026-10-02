//
//  GoalIntakeStore+Preview.swift
//  Linea
//
//  Preview-only factory: in-memory goals, no microphone in use, no network.
//

import Foundation

extension GoalIntakeStore {
    @MainActor
    static var preview: GoalIntakeStore {
        GoalIntakeStore(
            dictation: VoiceDictation(
                recorder: VoiceRecorder(),
                hasSpeechModel: false,
                makeTranscriber: { AppleSpeechTranscriber() },
                subject: "Цель",
                fallbackNotice: "Распознала системная диктовка — проверь текст."
            ),
            planStore: .preview
        )
    }
}
