//
//  AppleSpeechTranscriber.swift
//  Linea
//
//  Распознавание на самом телефоне: бесплатно, без сети, запись никуда не
//  уходит. Качество ниже облачного — для русского это уровень системной
//  диктовки, часто без знаков препинания.
//
//  Что есть для русского (проверено по документации и замерам, 23.09.2026):
//    • iOS 26+: новый `SpeechTranscriber` русского НЕ знает ни в 26, ни в 27,
//      русский есть только в `DictationTranscriber` — его и берём. Если
//      Apple добавит русский в новую модель, она подхватится сама;
//    • iOS 18–25: `SFSpeechRecognizer` строго на устройстве. Сетевой режим
//      не используем: у него предел около минуты, а итог дня — до пяти.
//
//  Разрешение на распознавание нужно только старому пути; новому хватает
//  доступа к микрофону, который уже дан для записи.
//

import Foundation
import AVFoundation
import CoreMedia
import OSLog
import Speech

nonisolated enum OnDeviceSpeechError: Error, LocalizedError {
    case localeUnsupported
    case notAuthorized
    case unavailable
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .localeUnsupported: return "На этом телефоне нет распознавания русской речи без сети."
        case .notAuthorized: return "Нет разрешения на распознавание речи. Включить: «Настройки» → Linea."
        case .unavailable: return "Распознавание речи на телефоне сейчас недоступно."
        case .noSpeech: return "В записи не распознано ни слова."
        }
    }
}

nonisolated struct AppleSpeechTranscriber: SpeechTranscribing {
    let id = "apple"

    init() {}

    func transcribe(audioAt url: URL, localeIdentifier: String) async throws -> Transcript {
        let locale = Locale(identifier: localeIdentifier)
        let text: String
        if #available(iOS 26.0, *) {
            text = try await Self.transcribeWithAnalyzer(url: url, locale: locale)
        } else {
            text = try await Self.transcribeWithRecognizer(url: url, locale: locale)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OnDeviceSpeechError.noSpeech }
        return Transcript(text: trimmed, transcriberID: id)
    }

    // MARK: iOS 26+: SpeechAnalyzer

    @available(iOS 26.0, *)
    private static func transcribeWithAnalyzer(url: URL, locale: Locale) async throws -> String {
        if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
            try await installAssets(for: [transcriber])
            let results = transcriber.results
            let collector = Task { () throws -> String in
                var parts: [String] = []
                for try await result in results where result.isFinal {
                    parts.append(String(result.text.characters))
                }
                return Self.joined(parts)
            }
            try await analyze(url, modules: [transcriber], collector: collector)
            return try await collector.value
        }

        guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) else {
            throw OnDeviceSpeechError.localeUnsupported
        }
        // Длинная диктовка: больше минуты, с расстановкой знаков, где язык её умеет.
        let transcriber = DictationTranscriber(locale: supported, preset: .longDictation)
        try await installAssets(for: [transcriber])
        let results = transcriber.results
        let collector = Task { () throws -> String in
            var parts: [String] = []
            for try await result in results where result.isFinal {
                parts.append(String(result.text.characters))
            }
            return Self.joined(parts)
        }
        try await analyze(url, modules: [transcriber], collector: collector)
        return try await collector.value
    }

    /// Модель распознавания скачивается один раз при первом использовании.
    @available(iOS 26.0, *)
    private static func installAssets(for modules: [any SpeechModule]) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            try await request.downloadAndInstall()
        }
    }

    /// Файл целиком: анализатор читает m4a сам, без ручной перекодировки.
    @available(iOS 26.0, *)
    private static func analyze(_ url: URL, modules: [any SpeechModule], collector: Task<String, any Error>) async throws {
        let audioFile = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: modules)
        do {
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collector.cancel()
            throw error
        }
    }

    private static func joined(_ parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: iOS 18–25: SFSpeechRecognizer на устройстве

    private static func transcribeWithRecognizer(url: URL, locale: Locale) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw OnDeviceSpeechError.unavailable
        }
        guard recognizer.supportsOnDeviceRecognition else { throw OnDeviceSpeechError.localeUnsupported }

        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw OnDeviceSpeechError.notAuthorized }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        let state = RecognitionState()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, any Error>) in
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                    state.finishOnce { continuation.resume(returning: text) }
                } else if let error {
                    state.finishOnce { continuation.resume(throwing: error) }
                }
            }
            state.retain(task)
        }
    }
}

/// Держит задачу распознавания живой и не даёт возобновить продолжение
/// дважды: система может прислать и результат, и ошибку.
private nonisolated final class RecognitionState: @unchecked Sendable {
    private let lock = NSLock()
    private var isFinished = false
    private var task: SFSpeechRecognitionTask?

    func retain(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        defer { lock.unlock() }
        if !isFinished { self.task = task }
    }

    func finishOnce(_ body: () -> Void) {
        lock.lock()
        let shouldRun = !isFinished
        isFinished = true
        task = nil
        lock.unlock()
        if shouldRun { body() }
    }
}

/// Основной распознаватель — модель на телефоне или облако; не справился —
/// системная диктовка. Итог дня не теряется ни при каком отказе.
nonisolated struct FallbackSpeechTranscriber: SpeechTranscribing {
    let primary: (any SpeechTranscribing)?
    let fallback: any SpeechTranscribing

    var id: String { primary?.id ?? fallback.id }

    func transcribe(audioAt url: URL, localeIdentifier: String) async throws -> Transcript {
        if let primary {
            do {
                return try await primary.transcribe(audioAt: url, localeIdentifier: localeIdentifier)
            } catch {
                LineaLog.checkIn.error("Распознавание \(primary.id, privacy: .public) не удалось, пробую диктовку: \(error.localizedDescription, privacy: .public)")
                var transcript = try await fallback.transcribe(audioAt: url, localeIdentifier: localeIdentifier)
                transcript.fallbackReason = error.localizedDescription
                return transcript
            }
        }
        return try await fallback.transcribe(audioAt: url, localeIdentifier: localeIdentifier)
    }
}
