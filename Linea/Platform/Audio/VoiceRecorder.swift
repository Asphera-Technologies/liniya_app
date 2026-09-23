//
//  VoiceRecorder.swift
//  Linea
//
//  Запись итога дня: до пяти минут, моно, AAC 16 кГц — для речи этого
//  достаточно, а пять минут весят около мегабайта. Файл лежит во временной
//  папке и удаляется сразу после распознавания: хранится текст, не голос.
//
//  Запись останавливается сама на пятой минуте и при звонке — тогда
//  распознаётся то, что успели сказать.
//

import Foundation
import AVFoundation
import Observation

nonisolated struct RecordedAudio: Sendable, Equatable {
    let url: URL
    let seconds: Int
}

@Observable
@MainActor
final class VoiceRecorder: NSObject {

    enum RecorderError: Error, LocalizedError {
        case permissionDenied
        case couldNotStart

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Нет доступа к микрофону. Включить: «Настройки» → Linea → «Микрофон»."
            case .couldNotStart: return "Не получилось начать запись."
            }
        }
    }

    /// Пять минут — столько, сколько просил заказчик.
    static let maxDuration: TimeInterval = 5 * 60

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// Громкость 0…1 для индикатора.
    private(set) var level: Double = 0
    /// Запись закончилась сама: истекли пять минут или прервал звонок.
    private(set) var finishedAutomatically: RecordedAudio?

    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private var interruptionObserver: (any NSObjectProtocol)?

    var isPermissionDenied: Bool { AVAudioApplication.shared.recordPermission == .denied }

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw RecorderError.permissionDenied }
        cancel()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("checkin-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.record(forDuration: Self.maxDuration) else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw RecorderError.couldNotStart
        }

        self.recorder = recorder
        elapsed = 0
        level = 0
        finishedAutomatically = nil
        isRecording = true
        observeInterruptions()
        startMetering()
    }

    /// Остановить и отдать запись.
    func stop() -> RecordedAudio? {
        guard let recorder, isRecording else { return nil }
        let seconds = Int(max(elapsed, recorder.currentTime).rounded())
        recorder.stop()
        let audio = RecordedAudio(url: recorder.url, seconds: seconds)
        tearDown()
        return audio
    }

    /// Отменить и стереть запись.
    func cancel() {
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        tearDown()
    }

    /// Удалить файл после распознавания: хранится текст, а не голос.
    static func discard(_ audio: RecordedAudio) {
        try? FileManager.default.removeItem(at: audio.url)
    }

    // MARK: Внутреннее

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRecording else { return }
                self.tick()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func tick() {
        guard let recorder else { return }
        recorder.updateMeters()
        let power = Double(recorder.averagePower(forChannel: 0))   // −160…0 дБ
        level = min(max((power + 50) / 50, 0), 1)
        elapsed = recorder.currentTime
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began else { return }
            MainActor.assumeIsolated { self?.finishAutomatically() }
        }
    }

    /// Звонок, будильник или пятая минута: сохранить то, что успели сказать.
    private func finishAutomatically() {
        guard isRecording else { return }
        finishedAutomatically = stop()
    }

    private func tearDown() {
        isRecording = false
        level = 0
        meterTask?.cancel()
        meterTask = nil
        recorder = nil
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension VoiceRecorder: AVAudioRecorderDelegate {
    /// Приходит и после нашего `stop()`, и когда истекли пять минут.
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.finishAutomatically() }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        Task { @MainActor in self.finishAutomatically() }
    }
}
