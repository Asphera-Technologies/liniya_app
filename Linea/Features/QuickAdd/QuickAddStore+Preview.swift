//
//  QuickAddStore+Preview.swift
//  Linea
//
//  Preview-only factory: in-memory tasks, no microphone in use, no network.
//

import Foundation

extension QuickAddStore {
    @MainActor
    static var preview: QuickAddStore {
        QuickAddStore(
            recorder: VoiceRecorder(),
            planStore: .preview,
            makeTranscriber: { AppleSpeechTranscriber() }
        )
    }
}
