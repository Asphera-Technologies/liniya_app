//
//  QuickAddStore.swift
//  Linea
//
//  Быстрое создание задачи: строка, чипы под ней, голос. Название —
//  единственное обязательное поле; остальное Linea берёт из сказанного или
//  ставит по умолчанию, а человек меняет чипом. Всё можно поправить потом в
//  карточке задачи.
//
//  Решает не стор, а ядро (`QuickTaskDraft`): стор хранит ввод, записывает
//  голос и сохраняет задачу через `PlanStore`. Голос — как в итоге дня:
//  распознаёт модель на телефоне, запись удаляется сразу после распознавания,
//  наружу ничего не уходит.
//

import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class QuickAddStore {

    enum VoicePhase: Equatable {
        case idle
        /// Идёт запись; кнопка микрофона её останавливает.
        case recording
        /// Модель на телефоне превращает запись в текст.
        case transcribing
    }

    /// Строка ввода и выбор в чипах.
    var draft = QuickTaskDraft()
    private(set) var voice: VoicePhase = .idle
    /// Не ошибка, а пояснение: «распознала диктовка», «запись остановилась».
    private(set) var notice: String?
    private(set) var isSaving = false
    /// Чем станет задача без слов о дне: «+ Задача» в плане и кнопка «+»
    /// создают задачу на сегодня.
    private(set) var defaultDay: TaskDay? = .today

    let recorder: VoiceRecorder
    /// Модель GigaAM в этой сборке есть. Без неё голос распознаёт диктовка.
    let hasSpeechModel: Bool

    private let planStore: PlanStore
    private let makeTranscriber: @MainActor () -> any SpeechTranscribing
    private let profileProvider: @MainActor () -> UserProfile
    private let timeProvider: @MainActor () -> TimeContext
    /// Запуск записи или распознавание — одна отменяемая работа.
    private var work: Task<Void, Never>?
    /// Выбирается один раз на открытие: второе «Добавить» не создаст копию.
    private var taskID = UUID()

    static let localeIdentifier = "ru_RU"

    init(
        recorder: VoiceRecorder,
        planStore: PlanStore,
        hasSpeechModel: Bool = false,
        makeTranscriber: @escaping @MainActor () -> any SpeechTranscribing,
        profile: @escaping @MainActor () -> UserProfile = { .default },
        time: @escaping @MainActor () -> TimeContext = { .live }
    ) {
        self.recorder = recorder
        self.planStore = planStore
        self.hasSpeechModel = hasSpeechModel
        self.makeTranscriber = makeTranscriber
        self.profileProvider = profile
        self.timeProvider = time
        recorder.onAutomaticStop = { [weak self] audio, _ in
            self?.transcribe(audio)
        }
    }

    var time: TimeContext { timeProvider() }

    /// Что получится из ввода прямо сейчас — это и показывают чипы.
    var resolution: QuickTaskResolution {
        draft.resolve(goals: planStore.goals, profile: profileProvider(), time: time, defaultDay: defaultDay)
    }

    /// Цели, к которым можно привязать задачу.
    var activeGoals: [LineaGoal] { planStore.activeGoals }

    func goal(with id: UUID?) -> LineaGoal? {
        guard let id else { return nil }
        return planStore.goals.first { $0.id == id }
    }

    // MARK: Экран

    /// Открыть ввод с чистого листа.
    func begin(defaultDay: TaskDay? = .today) {
        end()
        self.defaultDay = defaultDay
    }

    /// Экран закрыт: запись стирается, начатое распознавание отменяется.
    func end() {
        stopVoice()
        draft = QuickTaskDraft()
        notice = nil
        isSaving = false
        taskID = UUID()
    }

    // MARK: Чипы

    func chooseDay(_ day: TaskDay) {
        draft.day = day
    }

    /// Срок с часами; `nil` — «Без срока».
    func chooseDeadline(_ moment: Date?) {
        if let moment {
            draft.deadline = .at(moment)
        } else {
            draft.deadline = .noDeadline
        }
    }

    func chooseMinutes(_ minutes: Int) {
        draft.minutes = minutes
    }

    func choosePriority(_ priority: TaskPriority) {
        draft.priority = priority
    }

    /// Цель; `nil` — «Без цели».
    func chooseGoal(_ id: UUID?) {
        if let id {
            draft.goal = .linked(id)
        } else {
            draft.goal = .noGoal
        }
    }

    // MARK: Сохранение

    /// «Добавить». `true` — задача сохранена, экран можно закрывать.
    func save() async -> Bool {
        let resolution = self.resolution
        guard resolution.canSave, !isSaving else { return false }
        isSaving = true
        stopVoice()
        let task = resolution.task(id: taskID, createdAt: time.now)
        await planStore.saveTask(task)
        let parts = resolution.recognized.map(\.part.rawValue).joined(separator: ",")
        LineaLog.plan.notice("Быстрая задача: распознано [\(parts, privacy: .public)], цель \(resolution.goalID == nil ? "нет" : "есть", privacy: .public)")
        return true
    }

    // MARK: Голос

    /// Кнопка микрофона: начать запись, закончить её или ничего, пока идёт распознавание.
    func toggleVoice() {
        switch voice {
        case .idle: startRecording()
        case .recording: stopRecording()
        case .transcribing: break
        }
    }

    /// Приложение свернули: записи в фоне нет, задачу проще надиктовать заново.
    func appMovedToBackground() {
        guard voice == .recording else { return }
        stopVoice()
        notice = "Запись остановилась — приложение свернули."
    }

    private func startRecording() {
        notice = nil
        perform { await self.runStartRecording() }
    }

    private func runStartRecording() async {
        do {
            try await recorder.start()
            voice = .recording
        } catch is CancellationError {
            return
        } catch {
            LineaLog.plan.error("Запись задачи не началась: \(error.localizedDescription, privacy: .public)")
            notice = error.localizedDescription
        }
    }

    private func stopRecording() {
        guard let audio = recorder.stop() else {
            voice = .idle
            return
        }
        transcribe(audio)
    }

    private func transcribe(_ audio: RecordedAudio) {
        guard voice == .recording else {
            VoiceRecorder.discard(audio)
            return
        }
        voice = .transcribing
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
        voice = .idle

        switch result {
        case .success(let transcript):
            let spoken = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let typed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Сказанное дописывается к набранному: «Отчёт» + «завтра к шести».
            draft.text = typed.isEmpty ? spoken : "\(typed) \(spoken)"
            if transcript.fallbackReason != nil {
                notice = "Распознала системная диктовка — проверь название."
            }
            LineaLog.plan.notice("Задача голосом: \(transcript.transcriberID, privacy: .public), запись \(audio.seconds, privacy: .public) с, распознано за \(Self.seconds(since: started), privacy: .public) с")
        case .failure(let error):
            LineaLog.plan.error("Задача голосом не распозналась: \(error.localizedDescription, privacy: .public)")
            notice = "Не получилось распознать: \(error.localizedDescription)"
        }
    }

    private func stopVoice() {
        work?.cancel()
        work = nil
        recorder.cancel()
        voice = .idle
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
