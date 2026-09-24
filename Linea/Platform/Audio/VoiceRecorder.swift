//
//  VoiceRecorder.swift
//  Linea
//
//  Запись итога дня: до пяти минут, моно, AAC 16 кГц — для речи этого
//  достаточно, а пять минут весят около мегабайта. Файл лежит во временной
//  папке и удаляется сразу после распознавания: хранится текст, не голос.
//
//  Запись останавливается сама на пятой минуте и при звонке — тогда
//  распознаётся то, что успели сказать. В фоне записи нет: свернули
//  приложение — `CheckInStore` останавливает её так же, как кнопка «Стоп».
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

    /// Почему запись закончилась без кнопки «Стоп».
    enum AutomaticStop: Equatable {
        /// Истекли пять минут.
        case timeLimit
        /// Звонок, будильник, сбой записи.
        case interrupted
    }

    /// Пять минут — столько, сколько просил заказчик.
    static let maxDuration: TimeInterval = 5 * 60

    private(set) var isRecording = false
    /// Сколько записано, не больше пяти минут.
    private(set) var elapsed: TimeInterval = 0
    /// Громкость 0…1 для индикатора.
    private(set) var level: Double = 0

    /// Запись закончилась сама — сюда приходит то, что успели сказать.
    @ObservationIgnored var onAutomaticStop: (@MainActor (RecordedAudio, AutomaticStop) -> Void)?

    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private var interruptionObserver: (any NSObjectProtocol)?

    var isPermissionDenied: Bool { AVAudioApplication.shared.recordPermission == .denied }

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw RecorderError.permissionDenied }
        // Пока спрашивали разрешение, экран могли закрыть.
        try Task.checkCancellation()
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
        isRecording = true
        observeInterruptions()
        startMetering()
    }

    /// Остановить и отдать запись.
    func stop() -> RecordedAudio? {
        guard let recorder, isRecording else { return nil }
        let recorded = max(elapsed, recorder.currentTime.isFinite ? recorder.currentTime : 0)
        let seconds = Int(min(recorded, Self.maxDuration).rounded())
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
        guard let recorder, isRecording else { return }
        recorder.updateMeters()
        let power = Double(recorder.averagePower(forChannel: 0))   // −160…0 дБ
        level = power.isFinite ? min(max((power + 50) / 50, 0), 1) : 0
        let time = recorder.currentTime
        guard time.isFinite else { return }
        elapsed = min(time, Self.maxDuration)
        // Таймер самой записи может отстать от часов на экране — на
        // тестовом iPhone они дошли до «5:01». Пять минут отсчитываем сами.
        if time >= Self.maxDuration { finishAutomatically(.timeLimit) }
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began else { return }
            MainActor.assumeIsolated { self?.finishAutomatically(.interrupted) }
        }
    }

    /// Звонок, будильник или пятая минута: отдать то, что успели сказать.
    private func finishAutomatically(_ reason: AutomaticStop) {
        guard isRecording, let audio = stop() else { return }
        onAutomaticStop?(audio, reason)
    }

    /// Система остановила запись сама. Ответ прежней записи, пришедший,
    /// когда уже идёт новая, не в счёт: иначе он оборвал бы новую.
    fileprivate func recorderDidStop(recordingAt url: URL) {
        guard let recorder, recorder.url == url else { return }
        finishAutomatically(elapsed >= Self.maxDuration - 1 ? .timeLimit : .interrupted)
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
    /// Приходит и после нашего `stop()` — тогда запись уже снята и ответ
    /// ничего не делает, — и когда запись остановила система.
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor in self.recorderDidStop(recordingAt: url) }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        let url = recorder.url
        Task { @MainActor in self.recorderDidStop(recordingAt: url) }
    }
}
