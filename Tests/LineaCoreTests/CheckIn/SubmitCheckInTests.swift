import Testing
import Foundation
@testable import LineaCore

@Suite("Итог дня: сохранение")
struct SubmitCheckInTests {
    private let time = WowFixture.evening

    /// Вечер после рассказа из `CheckInFixture`, разобранного правилами.
    private func draft(_ transcript: String = CheckInFixture.transcript) -> CheckInDraft {
        let request = CheckInFixture.request(transcript)
        let extraction = RuleBasedCheckInExtractor().parse(request)
        return CheckInDraft.make(from: extraction, request: request, source: .voice(seconds: 64))
    }

    /// Утренний план wow-дня, принятый пользователем.
    private func plannedRecord() async -> DayRecord {
        let explainer = RuleBasedExplainer()
        let useCase = PlanDayUseCase(
            contextEngine: ContextEngine(providers: [FakeContextProvider(id: .healthKit, signals: WowFixture.healthSignals)]),
            decisionEngine: DecisionEngine(rules: [DayBriefRule()], renderer: explainer),
            nudgeEngine: NudgeEngine(renderer: explainer),
            explainer: explainer
        )
        let output = await useCase.run(PlanDayUseCase.Input(
            time: WowFixture.morning, tasks: WowFixture.tasks, goals: WowFixture.goals,
            history: WowFixture.history
        ))
        return AcceptPlanUseCase(nudgeEngine: NudgeEngine(renderer: explainer))
            .run(record: output.record, calibration: .default, time: WowFixture.morning).record
    }

    private func submit(_ draft: CheckInDraft, record: DayRecord?, memory: UserMemory = .empty, previous: CheckInEntry? = nil) -> SubmitCheckInUseCase.Output {
        SubmitCheckInUseCase().run(SubmitCheckInUseCase.Input(
            draft: draft, tasks: WowFixture.tasks, record: record, history: [],
            calibration: .default, memory: memory, previous: previous, time: time
        ))
    }

    // MARK: Черновик

    @Test("Черновик: уверенно понятое отмечено, остальное ждёт человека")
    func draftPreselection() {
        let draft = draft()
        let checked = Set(draft.tasks.filter(\.isDone).map(\.id))
        #expect(checked == [WowFixture.taskA, WowFixture.taskC, WowFixture.taskCall])
        #expect(draft.tasks.first { $0.id == WowFixture.taskB }?.note == "частично")
        #expect(draft.tasks.first { $0.id == WowFixture.taskWorkout }?.note == "не сделано")
        #expect(draft.plannedCount == 5)
        #expect(draft.workMinutes == 420)
        #expect(draft.memory.allSatisfy { $0.isAccepted })
    }

    @Test("Объём без слов человека — по оценкам отмеченных задач")
    func estimatedVolume() {
        var draft = draft("Сделал презентацию КП и ответил на письма.")
        #expect(draft.statedWorkMinutes == nil)
        #expect(draft.workMinutes == 90 + 30)
        draft.extra.append(CheckInDraft.ExtraLine(id: 9, title: "Звонок юристу", minutes: 20, isIncluded: true))
        #expect(draft.workMinutes == 140)
    }

    // MARK: Сохранение

    @Test("Сохранение: задачи закрыты и перенесены, дневник, память, оценка")
    func submitWowEvening() async throws {
        let record = await plannedRecord()
        let output = submit(draft(), record: record)

        // Закрыто то, что отмечено; время закрытия — момент итога.
        let closed = output.changedTasks.filter(\.isDone)
        #expect(Set(closed.map(\.id)) == [WowFixture.taskA, WowFixture.taskC, WowFixture.taskCall])
        #expect(closed.allSatisfy { $0.completedAt == time.now })

        // Незакрытое уехало на завтра и потеряло фиксированное время.
        let tomorrow = time.adding(days: 1, to: WowFixture.today)
        #expect(Set(output.movedTaskIDs) == [WowFixture.taskB, WowFixture.taskWorkout])
        let workout = try #require(output.changedTasks.first { $0.id == WowFixture.taskWorkout })
        #expect(workout.date == tomorrow)
        #expect(workout.scheduledStart == nil)

        // Дневник.
        let entry = output.entry
        #expect(entry.day == WowFixture.today)
        #expect(entry.source == .voice(seconds: 64))
        #expect(entry.report.completedPlannedCount == 3)
        #expect(entry.report.plannedCount == 5)
        #expect(entry.report.workMinutes == 420)
        #expect(entry.digest == "09.09, ср: сделано 3 из 5, работа 7 ч, день: тяжело, мало сил. Сделано: «Презентация КП», «Ответить на письма», «Созвон с командой». Не сделано: «Разработка Linea», «Тренировка». Ещё: «Созвонился с поставщиком».")

        // Память: явная просьба закреплена.
        let fact = try #require(output.memory.facts.first)
        #expect(fact.text == "После обеда я плохо соображаю")
        #expect(fact.isPinned)
        #expect(fact.source == .checkIn(day: WowFixture.today))
        #expect(output.addedFacts.count == 1)

        // День: план против факта, оценка, вечерний вопрос снят.
        let report = try #require(output.record.report)
        let focusIDs = Set((record.plan?.focusBlocks ?? []).compactMap(\.taskID))
        #expect(report.plannedTasks == focusIDs.count)
        #expect(report.plannedMinutes > 0)
        if focusIDs.contains(WowFixture.taskB) {
            #expect(report.completedPlannedMinutes < report.plannedMinutes)
        }
        #expect(output.record.rating == .hard)
        #expect(output.record.isReviewed)
        #expect(!output.record.nudges.contains { $0.kind == .eveningCheckIn })
        #expect(output.calibration.ratingsCount == 1)
    }

    @Test("Снятые галочки и выключенный перенос уважаются")
    func userCorrections() {
        var draft = draft()
        if let index = draft.tasks.firstIndex(where: { $0.id == WowFixture.taskCall }) { draft.tasks[index].isDone = false }
        draft.movesUnfinishedToTomorrow = false
        draft.memory[0].isAccepted = false
        draft.extra[0].isIncluded = false

        let output = submit(draft, record: nil)
        #expect(!output.changedTasks.contains { $0.id == WowFixture.taskCall })
        #expect(output.movedTaskIDs.isEmpty)
        #expect(output.memory.facts.isEmpty)
        #expect(output.entry.report.extra.isEmpty)
        // Дня в базе не было — он создаётся из итога.
        #expect(output.record.day == WowFixture.today)
        #expect(output.record.report?.completedPlannedTasks == 2)
    }

    @Test("Будущая встреча сегодня не переносится")
    func futureCommitmentStays() {
        let late = LineaTask(title: "Созвон с Азией", date: WowFixture.today, createdAt: WowFixture.created,
                             scheduledStart: WowFixture.moment(22, 30))
        let request = CheckInRequest(transcript: "Всё нормально.", day: WowFixture.today,
                                     tasks: [late], time: time)
        let draft = CheckInDraft.make(from: RuleBasedCheckInExtractor().parse(request), request: request, source: .text)
        #expect(draft.unfinishedToMove(tasks: [late], time: time).isEmpty)
    }

    @Test("Повторный итог дня заменяет прежний, а не копится")
    func redoReplaces() async {
        let first = submit(draft(), record: await plannedRecord())
        let second = submit(draft("Всё сделал, день отличный."), record: first.record, previous: first.entry)
        #expect(second.entry.id == first.entry.id)
        #expect(second.entry.createdAt == first.entry.createdAt)
        #expect(second.record.feedback.filter { $0.dayReport != nil }.count == 1)
        #expect(second.record.feedback.filter { $0.dayRating != nil }.count == 1)
        #expect(second.record.rating == .great)
    }

    @Test("Итог после полуночи закрывает задачи вчерашним днём")
    func afterMidnight() {
        let lateNight = WowFixture.time(0, 40, dayOffset: 1)
        let request = CheckInFixture.request(time: lateNight)
        let draft = CheckInDraft.make(from: RuleBasedCheckInExtractor().parse(request), request: request, source: .text)
        let output = SubmitCheckInUseCase().run(SubmitCheckInUseCase.Input(
            draft: draft, tasks: WowFixture.tasks, record: nil, history: [],
            calibration: .default, memory: .empty, previous: nil, time: lateNight
        ))
        let closedAt = output.changedTasks.compactMap(\.completedAt)
        #expect(!closedAt.isEmpty)
        #expect(closedAt.allSatisfy { lateNight.isSameDay($0, WowFixture.today) })
    }

    // MARK: Калибровка по факту

    @Test("Ёмкость дня учится на доле сделанного плана")
    func capacityFromCompletion() async {
        let record = await plannedRecord()
        var history: [DayRecord] = []
        // Три дня подряд закрыта только треть плана.
        for offset in 1...3 {
            var day = DayRecord(day: time.adding(days: -offset, to: WowFixture.today), snapshot: record.snapshot,
                                state: record.state, plan: record.plan, updatedAt: time.now)
            day.feedback.append(UserFeedback(at: time.now, kind: .dayReport(DayReportSummary(
                plannedTasks: 3, completedPlannedTasks: 1, plannedMinutes: 240, completedPlannedMinutes: 80, workMinutes: nil
            ))))
            history.append(day)
        }
        let calibration = FeedbackEngine().calibrate(history: history, previous: .default, time: time)
        #expect(calibration.capacityFactor < 0.8)
        // Без итогов и оценок калибровка не двигается.
        let untouched = FeedbackEngine().calibrate(history: [record], previous: .default, time: time)
        #expect(untouched.capacityFactor == Calibration.default.capacityFactor)
    }

    @Test("Итог дня снимает вечерний вопрос и в напоминаниях")
    func eveningRuleRespectsReport() async {
        let record = await plannedRecord()
        let output = submit(draft(), record: record)
        let context = NudgeContext(
            plan: output.record.plan!, snapshot: output.record.snapshot!, state: output.record.state!,
            feedback: output.record.feedback, existing: [], calibration: .default, config: .default,
            time: WowFixture.time(20, 45)
        )
        let rule = EveningCheckInRule().bound(to: RuleBasedExplainer())
        #expect(rule.nudges(context).isEmpty)
    }

    // MARK: Дневник

    @Test("Старая запись сжимается: рассказ уходит, итог остаётся")
    func compaction() {
        let output = submit(draft(), record: nil)
        let later = WowFixture.time(12, 0, dayOffset: CheckInEntry.compactionDays + 1)
        let compacted = output.entry.compacted(asOf: later)
        #expect(compacted.transcript == nil)
        #expect(compacted.digest == output.entry.digest)
        #expect(output.entry.compacted(asOf: WowFixture.time(12, 0, dayOffset: 5)).transcript != nil)
    }

    @Test("Запись дневника читается, даже если в ней не хватает полей")
    func lenientDecoding() throws {
        let json = #"{"id":"AAAAAAAA-0000-0000-0000-000000000001","day":"2026-09-08T21:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(CheckInEntry.self, from: Data(json.utf8))
        #expect(entry.source == .text)
        #expect(entry.digest.isEmpty)
        #expect(entry.report.completed.isEmpty)
    }
}
