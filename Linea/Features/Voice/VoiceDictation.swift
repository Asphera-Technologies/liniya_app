//
//  VoiceDictation.swift
//  Linea
//
//  Надиктовать текст в поле: запись, распознавание на телефоне, текст — туда,
//  где человек его ждёт. Один для быстрой задачи и новой цели. Распознаёт
//  модель GigaAM, встроенная в приложение (ADR-022), не справилась —
//  системная диктовка. Запись удаляется сразу после распознавания, наружу
//  ничего не уходит.
//

import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class VoiceDictation {

    enum Phase: Equatable {
        case idle
        /// Идёт запись; кнопка микрофона её останавливает.
        case recording
        /// Модель на телефоне превращает запись в текст.
        case transcribing
    }

    private(set) var phase: Phase = .idle
    /// Не ошибка, а пояснение: «распознала диктовка», «запись остановилась».
    private(set) var notice: String?

    let recorder: VoiceRecorder
    /// Модель GigaAM в этой сборке есть. Без неё голос распознаёт диктовка.
    let hasSpeechModel: Bool
    /// Распознанный текст — в поле экрана.
    @ObservationIgnored var onText: (@MainActor (String) -> Void)?

    private let makeTranscriber: @MainActor () -> any SpeechTranscribing
    /// Что надиктовано — для «Диагностики»: «Задача», «Цель».
    private let subject: String
    /// Пояснение, когда распознала системная диктовка.
    private let fallbackNotice: String
    /// Запуск записи или распознавание — одна отменяемая работа.
    private var work: Task<Void, Never>?

    static let localeIdentifier = "ru_RU"

    init(
        recorder: VoiceRecorder,
        hasSpeechModel: Bool,
        makeTranscriber: @escaping @MainActor () -> any SpeechTranscribing,
        subject: String,
        fallbackNotice: String
    ) {
        self.recorder = recorder
        self.hasSpeechModel = hasSpeechModel
        self.makeTranscriber = makeTranscriber
        self.subject = subject
        self.fallbackNotice = fallbackNotice
        recorder.onAutomaticStop = { [weak self] audio, _ in
            self?.transcribe(audio)
        }
    }

    /// Кнопка микрофона: начать запись, закончить её или ничего, пока идёт распознавание.
    func toggle() {
        switch phase {
        case .idle: startRecording()
        case .recording: stopRecording()
        case .transcribing: break
        }
    }

    /// Приложение свернули: записи в фоне нет, проще надиктовать заново.
    func appMovedToBackground() {
        guard phase == .recording else { return }
        cancel()
        notice = "Запись остановилась — приложение свернули."
    }

    /// Запись стирается, начатое распознавание отменяется.
    func cancel() {
        work?.cancel()
        work = nil
        recorder.cancel()
        phase = .idle
    }

    /// Экран закрыт: ещё и пояснение больше не нужно.
    func reset() {
        cancel()
        notice = nil
    }

    // MARK: Запись

    private func startRecording() {
        notice = nil
        perform { await self.runStartRecording() }
    }

    private func runStartRecording() async {
        do {
            try await recorder.start()
            phase = .recording
        } catch is CancellationError {
            return
        } catch {
            LineaLog.plan.error("\(self.subject, privacy: .public): запись не началась: \(error.localizedDescription, privacy: .public)")
            notice = error.localizedDescription
        }
    }

    private func stopRecording() {
        guard let audio = recorder.stop() else {
            phase = .idle
            return
        }
        transcribe(audio)
    }

    // MARK: Распознавание

    private func transcribe(_ audio: RecordedAudio) {
        guard phase == .recording else {
            VoiceRecorder.discard(audio)
            return
        }
        phase = .transcribing
        perform { await self.runTranscription(audio) }
    }

    private func runTranscription(_ audio: RecordedAudio) async {
        let started = ContinuousClock.now
        let result: Result<Transcript, any Error>
        do {
            result = .success(try await makeTranscriber().transcribe(audioAt: audio.url, localeIdentifier: Self.localeIdentifier))
        } catch {
            result = .failure(error)
        }
        // Голос не хранится: после распознавания остаётся только текст.
        VoiceRecorder.discard(audio)
        guard !Task.isCancelled else { return }
        phase = .idle

        switch result {
        case .success(let transcript):
            onText?(transcript.text.trimmingCharacters(in: .whitespacesAndNewlines))
            if transcript.fallbackReason != nil {
                notice = fallbackNotice
            }
            LineaLog.plan.notice("\(self.subject, privacy: .public) голосом: \(transcript.transcriberID, privacy: .public), запись \(audio.seconds, privacy: .public) с, распознано за \(Self.seconds(since: started), privacy: .public) с")
        case .failure(let error):
            LineaLog.plan.error("\(self.subject, privacy: .public) голосом не распозналась: \(error.localizedDescription, privacy: .public)")
            notice = "Не получилось распознать: \(error.localizedDescription)"
        }
    }

    private func perform(_ operation: @escaping @MainActor () async -> Void) {
        work?.cancel()
        work = Task { await operation() }
    }

    /// Секунды с начала распознавания — для «Диагностики».
    private static func seconds(since start: ContinuousClock.Instant) -> String {
        let elapsed = start.duration(to: .now).components
        return String(format: "%.1f", Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
    }
}
