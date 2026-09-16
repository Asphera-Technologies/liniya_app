//
//  CalendarConnector.swift
//  Linea
//
//  Календарь как коннектор. Здесь — вся логика отбора событий, и она
//  Foundation-only: какие события вообще занимают время, как назвать
//  занятость и к какому виду её отнести. EventKit остаётся в `Linea/Data`
//  и только переводит `EKEvent` в `CalendarEvent`.
//
//  Так правила проверяются тестами на Linux, а на Mac остаётся тонкий
//  адаптер, где ломаться почти нечему.
//
//  Ядро при этом не меняется: событие превращается в сигнал `.commitment`,
//  который планировщик уже умеет вычитать из свободных окон, а нудж —
//  считать «до следующего обязательства».
//

import Foundation

/// Событие календаря в терминах Linea. Ровно те поля, от которых зависит
/// решение занимать время или нет.
nonisolated struct CalendarEvent: Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    /// Событие на весь день (день рождения, праздник, отпуск).
    let isAllDay: Bool
    /// Помечено в календаре как «занят». События со статусом «свободен»
    /// время не занимают.
    let isBusy: Bool
    let isCanceled: Bool
    /// Название календаря — попадает в атрибуты сигнала для диагностики.
    let calendarTitle: String?

    init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        isBusy: Bool = true,
        isCanceled: Bool = false,
        calendarTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = max(start, end)
        self.isAllDay = isAllDay
        self.isBusy = isBusy
        self.isCanceled = isCanceled
        self.calendarTitle = calendarTitle
    }

    var durationMinutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

/// Календарь умеет две вещи: отдавать сигналы за день (это нужно движку) и
/// показывать события за произвольный период (это нужно экрану «План», где
/// пользователь листает недели). Второе — не часть контекста дня, поэтому
/// объявлено отдельно, а не запихнуто в `ContextProvider`.
nonisolated protocol CalendarConnecting: ContextProvider {
    func commitments(in interval: DateInterval, time: TimeContext) async throws -> [Commitment]
}

/// Превращает события в сигналы `.commitment`.
nonisolated struct CalendarSignalMapper: Sendable {
    /// Событие короче этого времени не считается занятостью: календари полны
    /// пятиминутных пометок, из-за которых день распадался бы на осколки.
    var minimumMinutes: Int
    /// Событие длиннее этого — скорее «поездка» или «отпуск», чем встреча;
    /// вычитать из дня его целиком бессмысленно.
    var maximumHours: Int

    init(minimumMinutes: Int = 10, maximumHours: Int = 12) {
        self.minimumMinutes = minimumMinutes
        self.maximumHours = maximumHours
    }

    /// Отбирает события, которые действительно занимают время в `window`.
    func blockingEvents(_ events: [CalendarEvent], in window: DateInterval) -> [CalendarEvent] {
        events
            .filter { event in
                guard !event.isAllDay, !event.isCanceled, event.isBusy else { return false }
                guard event.durationMinutes >= minimumMinutes else { return false }
                guard event.durationMinutes <= maximumHours * 60 else { return false }
                return event.end > window.start && event.start < window.end
            }
            .sorted { lhs, rhs in
                lhs.start != rhs.start ? lhs.start < rhs.start : lhs.id < rhs.id
            }
    }

    /// Те же правила отбора, но сразу в виде обязательств — для экранов,
    /// которым не нужен весь контекст дня.
    func commitments(from events: [CalendarEvent], in window: DateInterval, source: ProviderID) -> [Commitment] {
        blockingEvents(events, in: window).map { event in
            Commitment(
                id: "calendar-\(event.id)",
                title: event.title.isEmpty ? "Событие" : event.title,
                start: event.start,
                end: event.end,
                kind: CommitmentKind.inferred(fromTitle: event.title, default: .meeting),
                source: source
            )
        }
    }

    func signals(from events: [CalendarEvent], in window: DateInterval, source: ProviderID) -> [ContextSignal] {
        blockingEvents(events, in: window).map { event in
            var attributes: [String: String] = [
                SignalAttribute.label: event.title.isEmpty ? "Событие" : event.title,
                SignalAttribute.commitmentKind: CommitmentKind.inferred(fromTitle: event.title, default: .meeting).rawValue,
                SignalAttribute.eventID: event.id,
            ]
            if let calendarTitle = event.calendarTitle { attributes["calendar"] = calendarTitle }
            return ContextSignal(
                kind: .commitment,
                value: .interval(nil),
                start: event.start,
                end: event.end,
                source: source,
                attributes: attributes
            )
        }
    }
}
