//
//  CalendarContextProvider.swift
//  Linea
//
//  Календарь как источник занятого времени. Адаптер намеренно тонкий: он
//  переводит `EKEvent` в `CalendarEvent` и отдаёт решение о том, что считать
//  занятостью, в `CalendarSignalMapper` (ядро, покрыто тестами).
//
//  Доступ здесь только читается, но не запрашивается: диалог разрешения
//  должен появляться по нажатию в «Профиле», а не посреди пересчёта плана.
//

import EventKit
import Foundation

nonisolated final class CalendarContextProvider: ContextProvider {
    let id: ProviderID = .calendar
    let displayName = "Календарь"
    let provides: Set<SignalKind> = [.commitment]

    private nonisolated(unsafe) let store: EKEventStore
    private let mapper: CalendarSignalMapper

    init(store: EKEventStore, mapper: CalendarSignalMapper = CalendarSignalMapper()) {
        self.store = store
        self.mapper = mapper
    }

    func fetchContext(_ request: ContextRequest) async throws -> ProviderFetchResult {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return ProviderFetchResult(signals: [], status: .unauthorized)
        }
        let window = request.day
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        let events = store.events(matching: predicate).map(Self.event)
        let signals = mapper.signals(from: events, in: window, source: id)
        return ProviderFetchResult(signals: signals, status: signals.isEmpty ? .noData : .ready)
    }

    /// `EKEvent` → доменное событие. Ни одного решения здесь не принимается.
    private static func event(_ event: EKEvent) -> CalendarEvent {
        CalendarEvent(
            id: event.eventIdentifier ?? "\(event.calendarItemIdentifier)",
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            // «Свободен» в календаре означает, что время не занято.
            isBusy: event.availability != .free,
            isCanceled: event.status == .canceled,
            calendarTitle: event.calendar?.title
        )
    }
}

/// Разрешение на календарь: статус и запрос. Отдельно от провайдера, потому
/// что спрашивать должен экран, а читать — движок.
@MainActor
enum CalendarAccess {
    static var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    static var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted || status == .writeOnly
    }

    /// Показывает системный диалог, если решение ещё не принято.
    static func request(_ store: EKEventStore) async -> Bool {
        if isAuthorized { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }
}
