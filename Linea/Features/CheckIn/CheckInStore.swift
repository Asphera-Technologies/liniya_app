//
//  CheckInStore.swift
//  Linea
//
//  «Итог дня» от первого нажатия до сохранения:
//    рассказ голосом или текстом → распознавание → разбор → проверка → сохранение.
//
//  Решает, кто распознаёт и кто разбирает: если человек разрешил облако в
//  «Профиле», это Grok, иначе телефон и правила. Облако не ответило —
//  работу молча подхватывает телефон, а экран честно говорит, что случилось.
//  Сохраняет через `SubmitCheckInUseCase`: сама ничего не решает о задачах
//  и калибровке.
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
    /// Не ошибка, а пояснение: «облако не ответило, распознал телефон».
    private(set) var notice: String?
    /// Кто распознал последнюю запись.
    private(set) var transcriberID: String?
    /// День, о котором рассказ.
    private(set) var day: Date

    let recorder: VoiceRecorder
    /// Облачная модель настроена (ключ на месте).
    let isCloudAvailable: Bool

    private var source: CheckInSource = .text
    private let planStore: PlanStore
    private let intelligence: IntelligenceStore
    private let memory: MemoryStore
    private let loadProfile: @MainActor () async -> UserProfile
    private let makeTranscriber: @MainActor (_ useCloud: Bool, _ keyterms: [String]) -> any SpeechTranscribing
    private let makeExtractor: @MainActor (_ useCloud: Bool) -> any CheckInExtracting
    private let submitUseCase: SubmitCheckInUseCase
    private let timeProvider: @MainActor () -> TimeContext

    static let localeIdentifier = "ru_RU"

    init(
        recorder: VoiceRecorder,
        planStore: PlanStore,
        intelligence: IntelligenceStore,
        memory: MemoryStore,
        isCloudAvailable: Bool,
        loadProfile: @escaping @MainActor () async -> UserProfile,
        makeTranscriber: @escaping @MainActor (_ useCloud: Bool, _ keyterms: [String]) -> any SpeechTranscribing,
        makeExtractor: @escaping @MainActor (_ useCloud: Bool) -> any CheckInExtracting,
        submitUseCase: SubmitCheckInUseCase = SubmitCheckInUseCase(),
        time: @escaping @MainActor () -> TimeContext = { .live }
    ) {
        self.recorder = recorder
        self.planStore = planStore
        self.intelligence = intelligence
        self.memory = memory
        self.isCloudAvailable = isCloudAvailable
        self.loadProfile = loadProfile
        self.makeTranscriber = makeTranscriber
        self.makeExtractor = makeExtractor
        self.submitUseCase = submitUseCase
        self.timeProvider = time
        self.day = time().today
    }

    var time: TimeContext { timeProvider() }

    /// Уходит ли итог дня в облако — по согласию человека. Читается из
    /// сохранённого профиля при каждом открытии экрана.
    private(set) var usesCloud = false

    /// День, о котором рассказывают: до четырёх утра — ещё вчерашний.
    static func checkInDay(at time: TimeContext) -> Date {
        time.timeOfDay(of: time.now).hour < 4 ? time.adding(days: -1, to: time.today) : time.today
    }

    /// Итог этого дня уже есть — повторный рассказ его заменит.
    var hasSavedEntry: Bool { memory.entry(for: day) != nil }

    // MARK: Начало

    /// Открыть экран: новый рассказ или правка сохранённого.
    func begin() async {
        recorder.cancel()
        day = Self.checkInDay(at: time)
        usesCloud = isCloudAvailable && (await loadProfile()).isCloudCheckInEnabled
        await memory.loadIfNeeded()
        draft = nil
        savedEntry = nil
        errorMessage = nil
        notice = nil
        transcriberID = nil
        if let existing = memory.entry(for: day), let previous = existing.transcript, !previous.isEmpty {
            text = previous
            source = existing.source
            phase = .writing
        } else {
            text = ""
            source = .text
            phase = .start
        }
    }

    // MARK: Голос

    func startRecording() async {
        errorMessage = nil
        notice = nil
        do {
            try await recorder.start()
            phase = .recording
        } catch {
            LineaLog.checkIn.error("Запись не началась: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            phase = .writing
        }
    }

    func stopRecording() async {
        guard let audio = recorder.stop() else { return }
        await transcribe(audio)
    }

    /// Запись остановилась сама: пять минут или звонок.
    func finishAutomaticRecording() async {
        guard phase == .recording, let audio = recorder.finishedAutomatically else { return }
        notice = audio.seconds >= Int(VoiceRecorder.maxDuration) - 1 ? "Пять минут — запись остановилась сама." : "Запись прервалась — распознаю то, что записалось."
        await transcribe(audio)
    }

    func cancelRecording() {
        recorder.cancel()
        phase = .start
    }

    private func transcribe(_ audio: RecordedAudio) async {
        phase = .transcribing
        source = .voice(seconds: audio.seconds)
        let transcriber = makeTranscriber(usesCloud, keyterms())
        let result: Result<Transcript, any Error>
        do {
            result = .success(try await transcriber.transcribe(audioAt: audio.url, localeIdentifier: Self.localeIdentifier))
        } catch {
            result = .failure(error)
        }
        // Голос не хранится: после распознавания остаётся только текст.
        VoiceRecorder.discard(audio)

        switch result {
        case .success(let transcript):
            transcriberID = transcript.transcriberID
            text = transcript.text
            if let reason = transcript.fallbackReason {
                notice = "Облако не ответило (\(reason)) — распознал телефон, точность ниже."
            }
            LineaLog.checkIn.notice("Распознано: \(transcript.transcriberID, privacy: .public), секунд \(audio.seconds, privacy: .public), символов \(transcript.text.count, privacy: .public)")
            await analyze()
        case .failure(let error):
            LineaLog.checkIn.error("Распознавание не удалось: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Не получилось распознать: \(error.localizedDescription) Можно написать текстом."
            phase = .writing
        }
    }

    /// Подсказки распознавателю: названия задач дня и латинские слова из них.
    private func keyterms() -> [String] {
        let titles = CheckInRequest.relevantTasks(from: planStore.tasks, day: day, time: time).map(\.title)
        let latin = titles.flatMap { title in
            RussianWords.tokens(title).map(\.original).filter { word in
                word.count >= 3 && word.unicodeScalars.allSatisfy(\.isASCII)
            }
        }
        return ["Linea"] + latin + titles
    }

    // MARK: Текст

    func switchToText() {
        recorder.cancel()
        errorMessage = nil
        phase = .writing
    }

    /// Разобрать рассказ: моделью, если разрешено, иначе правилами.
    func analyze() async {
        let story = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !story.isEmpty else {
            errorMessage = "Расскажи хотя бы пару фраз."
            phase = .writing
            return
        }
        phase = .analyzing
        errorMessage = nil

        let time = self.time
        let cloud = usesCloud
        let request = CheckInRequest(
            transcript: story,
            day: day,
            tasks: CheckInRequest.relevantTasks(from: planStore.tasks, day: day, time: time),
            knownFacts: cloud ? memory.knownFacts() : [],
            time: time
        )
        do {
            let extraction = try await makeExtractor(cloud).extract(request)
            if cloud && extraction.extractorID == RuleBasedCheckInExtractor().id {
                notice = [notice, "Модель не ответила — разобрал телефон, проверь внимательнее."].compactMap { $0 }.joined(separator: " ")
            }
            LineaLog.checkIn.notice("Разобрано: \(extraction.extractorID, privacy: .public), задач \(extraction.outcomes.count, privacy: .public), фактов \(extraction.memory.count, privacy: .public)")
            draft = CheckInDraft.make(from: extraction, request: request, source: source)
            phase = .review
        } catch {
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

    func submit() async {
        guard let draft else { return }
        phase = .saving
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
}
