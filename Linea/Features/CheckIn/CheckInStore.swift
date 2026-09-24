//
//  CheckInStore.swift
//  Linea
//
//  «Итог дня» от первого нажатия до сохранения:
//    рассказ голосом или текстом → распознавание → разбор → проверка → сохранение.
//
//  Всё происходит на телефоне, наружу итог дня не уходит (ADR-021): голос
//  распознаёт встроенная модель GigaAM (ADR-022), рассказ разбирают правила. Сохраняет через `SubmitCheckInUseCase`: сама
//  ничего не решает о задачах и калибровке.
//
//  Запись, распознавание и разбор идут одной отменяемой задачей. Закрыли
//  экран — задача отменяется, запись стирается, и поздний ответ прежнего
//  рассказа уже ничего не трогает: следующий начинается с чистого листа.
//

import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class CheckInStore {

    enum Phase: Equatable {
        /// Выбор: рассказать голосом или написать.
        case start
        case recording
        case transcribing
        /// Ввод или правка текста рассказа.
        case writing
        case analyzing
        /// Экран «Проверь».
        case review
        case saving
        case saved
    }

    private(set) var phase: Phase = .start
    /// Рассказ: распознанный или набранный. Правится на экране.
    var text = ""
    /// Черновик для экрана проверки; галочки правит человек.
    var draft: CheckInDraft?
    private(set) var savedEntry: CheckInEntry?
    /// Что пошло не так и почему экран вернулся назад.
    private(set) var errorMessage: String?
    /// Не ошибка, а пояснение: «запись прервалась», «распознала диктовка».
    private(set) var notice: String?
    /// Кто распознал последнюю запись.
    private(set) var transcriberID: String?
    /// День, о котором рассказ.
    private(set) var day: Date

    let recorder: VoiceRecorder
    /// Модель GigaAM в этой сборке есть. Без неё голос распознаёт диктовка.
    let hasSpeechModel: Bool

    private var source: CheckInSource = .text
    /// Что сейчас идёт: запуск записи, распознавание или разбор.
    private var work: Task<Void, Never>?
    /// Запись, остановленная сворачиванием: распознаётся, когда человек вернётся.
    private var pendingAudio: RecordedAudio?
    private var isStartingRecording = false

    private let planStore: PlanStore
    private let intelligence: IntelligenceStore
    private let memory: MemoryStore
    private let makeTranscriber: @MainActor () -> any SpeechTranscribing
    private let extractor: any CheckInExtracting
    private let submitUseCase: SubmitCheckInUseCase
    private let timeProvider: @MainActor () -> TimeContext

    static let localeIdentifier = "ru_RU"

    init(
        recorder: VoiceRecorder,
        planStore: PlanStore,
        intelligence: IntelligenceStore,
        memory: MemoryStore,
        hasSpeechModel: Bool = false,
        makeTranscriber: @escaping @MainActor () -> any SpeechTranscribing,
        extractor: any CheckInExtracting = FallbackCheckInExtractor(primary: nil),
        submitUseCase: SubmitCheckInUseCase = SubmitCheckInUseCase(),
        time: @escaping @MainActor () -> TimeContext = { .live }
    ) {
        self.recorder = recorder
        self.planStore = planStore
        self.intelligence = intelligence
        self.memory = memory
        self.hasSpeechModel = hasSpeechModel
        self.makeTranscriber = makeTranscriber
        self.extractor = extractor
        self.submitUseCase = submitUseCase
        self.timeProvider = time
        self.day = time().today
        recorder.onAutomaticStop = { [weak self] audio, reason in
            self?.recordingStoppedAutomatically(audio, reason: reason)
        }
    }

    var time: TimeContext { timeProvider() }

    /// День, о котором рассказывают: до четырёх утра — ещё вчерашний.
    static func checkInDay(at time: TimeContext) -> Date {
        time.timeOfDay(of: time.now).hour < 4 ? time.adding(days: -1, to: time.today) : time.today
    }

    /// Итог этого дня уже есть — повторный рассказ его заменит.
    var hasSavedEntry: Bool { memory.entry(for: day) != nil }

    // MARK: Экран

    /// Открыть экран: новый рассказ или правка сохранённого.
    func begin() async {
        end()
        await memory.loadIfNeeded()
        // Экран успели закрыть, пока читалась память.
        guard !Task.isCancelled else { return }
        // Человек уже начал рассказывать — сохранённым текстом не перебиваем.
        guard phase == .start, text.isEmpty else { return }
        if let existing = memory.entry(for: day), let previous = existing.transcript, !previous.isEmpty {
            text = previous
            source = existing.source
            phase = .writing
        }
    }

    /// Экран закрыт. Запись стирается, распознавание и разбор отменяются,
    /// в следующий раз экран откроется с начала. Сохранение не прерывается:
    /// во время него экран не закрыть.
    func end() {
        guard phase != .saving else { return }
        stopWork()
        if let pendingAudio { VoiceRecorder.discard(pendingAudio) }
        pendingAudio = nil
        day = Self.checkInDay(at: time)
        phase = .start
        text = ""
        source = .text
        draft = nil
        savedEntry = nil
        errorMessage = nil
        notice = nil
        transcriberID = nil
    }

    /// Остановить всё, что идёт: запись, распознавание, разбор. Экран не
    /// меняется — так «Закрыть» гасит микрофон сразу, а не после анимации.
    func stopWork() {
        guard phase != .saving else { return }
        work?.cancel()
        work = nil
        recorder.cancel()
    }

    // MARK: Голос

    func startRecording() {
        guard phase == .start || phase == .writing, !isStartingRecording else { return }
        isStartingRecording = true
        errorMessage = nil
        notice = nil
        perform { await self.runStartRecording() }
    }

    func stopRecording() {
        guard phase == .recording, let audio = recorder.stop() else { return }
        transcribe(audio)
    }

    func cancelRecording() {
        stopWork()
        phase = .start
    }

    /// Приложение свернули. Записи в фоне нет: она останавливается, а
    /// распознаётся, когда человек вернётся, — в фоне iOS может в любой
    /// момент прервать работу, и рассказ бы потерялся.
    func appMovedToBackground() {
        guard phase == .recording, let audio = recorder.stop() else { return }
        pendingAudio = audio
        source = .voice(seconds: audio.seconds)
        phase = .transcribing
        addNotice("Приложение свернули — запись остановилась. Распознаю то, что успели рассказать.")
        LineaLog.checkIn.notice("Запись остановлена: приложение свёрнуто, секунд \(audio.seconds, privacy: .public)")
    }

    func appBecameActive() {
        guard let audio = pendingAudio else { return }
        pendingAudio = nil
        transcribe(audio)
    }

    /// Пять минут, звонок или сбой записи: распознаём то, что успели сказать.
    private func recordingStoppedAutomatically(_ audio: RecordedAudio, reason: VoiceRecorder.AutomaticStop) {
        guard phase == .recording else {
            VoiceRecorder.discard(audio)
            return
        }
        addNotice(reason == .timeLimit ? "Пять минут — запись остановилась сама." : "Запись прервалась — распознаю то, что записалось.")
        transcribe(audio)
    }

    private func runStartRecording() async {
        defer { isStartingRecording = false }
        do {
            try await recorder.start()
            phase = .recording
        } catch is CancellationError {
            return
        } catch {
            LineaLog.checkIn.error("Запись не началась: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            phase = .writing
        }
    }

    private func transcribe(_ audio: RecordedAudio) {
        phase = .transcribing
        source = .voice(seconds: audio.seconds)
        perform { await self.runTranscription(audio) }
    }

    private func runTranscription(_ audio: RecordedAudio) async {
        let transcriber = makeTranscriber()
        let started = ContinuousClock.now
        let result: Result<Transcript, any Error>
        do {
            result = .success(try await transcriber.transcribe(audioAt: audio.url, localeIdentifier: Self.localeIdentifier))
        } catch {
            result = .failure(error)
        }
        // Голос не хранится: после распознавания остаётся только текст.
        VoiceRecorder.discard(audio)
        // Экран закрыли или начали заново — этот ответ уже никому не нужен.
        guard !Task.isCancelled else { return }

        switch result {
        case .success(let transcript):
            transcriberID = transcript.transcriberID
            text = transcript.text
            if let reason = transcript.fallbackReason {
                addNotice("Основной способ распознавания не сработал (\(reason)) — распознала системная диктовка, точность ниже.")
            }
            LineaLog.checkIn.notice("Распознано: \(transcript.transcriberID, privacy: .public), запись \(audio.seconds, privacy: .public) с, за \(Self.seconds(since: started), privacy: .public) с, символов \(transcript.text.count, privacy: .public)")
            await runAnalysis()
        case .failure(let error):
            LineaLog.checkIn.error("Распознавание не удалось за \(Self.seconds(since: started), privacy: .public) с: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Не получилось распознать: \(error.localizedDescription) Можно написать текстом."
            phase = .writing
        }
    }

    // MARK: Текст

    func switchToText() {
        stopWork()
        errorMessage = nil
        phase = .writing
    }

    /// «Разобрать»: рассказ разбирают правила на телефоне.
    func analyze() {
        guard phase == .writing else { return }
        phase = .analyzing
        perform { await self.runAnalysis() }
    }

    private func runAnalysis() async {
        let story = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !story.isEmpty else {
            errorMessage = "Расскажи хотя бы пару фраз."
            phase = .writing
            return
        }
        phase = .analyzing
        errorMessage = nil

        let time = self.time
        let request = CheckInRequest(
            transcript: story,
            day: day,
            tasks: CheckInRequest.relevantTasks(from: planStore.tasks, day: day, time: time),
            knownFacts: memory.knownFacts(),
            time: time
        )
        let started = ContinuousClock.now
        do {
            let extraction = try await extractor.extract(request)
            guard !Task.isCancelled else { return }
            LineaLog.checkIn.notice("Разобрано: \(extraction.extractorID, privacy: .public) за \(Self.seconds(since: started), privacy: .public) с, задач \(extraction.outcomes.count, privacy: .public), фактов \(extraction.memory.count, privacy: .public)")
            draft = CheckInDraft.make(from: extraction, request: request, source: source)
            phase = .review
        } catch {
            guard !Task.isCancelled else { return }
            LineaLog.checkIn.error("Разбор не удался: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            phase = .writing
        }
    }

    /// Что уедет на завтра, если перенос включён.
    var movingTitles: [String] {
        guard let draft else { return [] }
        return draft.unfinishedToMove(tasks: planStore.tasks, time: time).map(\.title)
    }

    /// Вернуться к тексту рассказа, чтобы поправить и разобрать заново.
    func editStory() {
        phase = .writing
    }

    // MARK: Сохранение

    /// «Сохранить итог». Второе нажатие ничего не делает: фаза уже другая.
    func save() {
        guard phase == .review, let draft else { return }
        phase = .saving
        // Не через `perform`: сохранение не отменяется, его доводят до конца.
        Task { await self.runSubmit(draft) }
    }

    private func runSubmit(_ draft: CheckInDraft) async {
        let time = self.time
        let context = await intelligence.checkInContext(for: draft.day)
        let output = submitUseCase.run(SubmitCheckInUseCase.Input(
            draft: draft,
            tasks: planStore.tasks,
            record: context.record,
            history: context.history,
            calibration: context.calibration,
            memory: memory.memory,
            previous: memory.entry(for: draft.day),
            time: time
        ))

        await memory.store(entry: output.entry, memory: output.memory)
        // Сначала день (план против факта), потом задачи: их сохранение
        // пересобирает план, и пересборка должна увидеть уже записанный итог.
        await intelligence.applyCheckIn(record: output.record, calibration: output.calibration)
        await planStore.saveTasks(output.changedTasks)

        LineaLog.checkIn.notice("Итог сохранён: закрыто \(output.changedTasks.filter(\.isDone).count, privacy: .public), перенесено \(output.movedTaskIDs.count, privacy: .public), новых фактов \(output.addedFacts.count, privacy: .public)")
        savedEntry = output.entry
        phase = .saved
    }

    // MARK: Мелочи

    /// Новая работа сменяет прежнюю: та отменяется, и её ответ отбрасывается.
    private func perform(_ operation: @escaping @MainActor () async -> Void) {
        work?.cancel()
        work = Task { await operation() }
    }

    private func addNotice(_ message: String) {
        guard notice?.contains(message) != true else { return }
        notice = [notice, message].compactMap { $0 }.joined(separator: " ")
    }

    /// Секунды с начала шага — для «Диагностики»: видно, что именно было медленным.
    private static func seconds(since start: ContinuousClock.Instant) -> String {
        let elapsed = start.duration(to: .now).components
        return String(format: "%.1f", Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
    }
}
