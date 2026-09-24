//
//  NetworkMonitor.swift
//  Linea
//
//  Есть ли сейчас сеть. Без сети облако не зовут: запрос всё равно не
//  дойдёт, а ждать его отказа — лишние секунды на экране «Разбираю…».
//  Состояние знает сама система (NWPathMonitor), запросов наружу нет.
//

import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkMonitor {
    /// Пока система не ответила, сеть считается доступной: так облако
    /// не отключится зря в первую долю секунды после запуска.
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            MainActor.assumeIsolated { self?.isOnline = online }
        }
        // Обновления приходят на главную очередь — там их и читают.
        monitor.start(queue: .main)
    }
}
