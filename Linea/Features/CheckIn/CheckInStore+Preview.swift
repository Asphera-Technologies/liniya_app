//
//  CheckInStore+Preview.swift
//  Linea
//
//  Preview-only factories: in-memory storage, no microphone, no network.
//  The check-in in a preview is parsed by the on-device rules.
//

import Foundation
import SwiftData

extension MemoryStore {
    @MainActor
    static var preview: MemoryStore {
        let context = PreviewContainer.shared.mainContext
        return MemoryStore(
            memoryRepository: LocalMemoryRepository(context: context),
            checkInRepository: LocalCheckInRepository(context: context)
        )
    }
}

extension CheckInStore {
    @MainActor
    static var preview: CheckInStore {
        CheckInStore(
            recorder: VoiceRecorder(),
            planStore: .preview,
            intelligence: .preview,
            memory: .preview,
            makeTranscriber: { AppleSpeechTranscriber() }
        )
    }
}
