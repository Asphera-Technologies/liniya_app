//
//  TaskKind.swift
//  Linea
//
//  Внутренний тип задачи (`task_type` в постановке): зачем задача вообще
//  существует. Одной связи с целью мало, чтобы балансировать день: «Оплатить
//  интернет» и «Позвонить другу» обе без цели, но первая — обслуживание быта,
//  а вторая — личное. Тип определяет Linea сама (`TaskClassifier`) по
//  названию, связи с целью и времени; в основном интерфейсе его не видно.
//  Человек может поправить его в карточке задачи — тогда хранится выбор
//  человека (`LineaTask.kindOverride`).
//

import Foundation

nonisolated enum TaskKind: String, Codable, CaseIterable, Sendable {
    /// Шаг к цели или проекту: «Подготовить релиз».
    case goal
    /// Обещано кому-то: есть получатель или встреча — «Отправить документ клиенту».
    case obligation
    /// Поддержание быта: счета, покупки, ремонт, врачи — «Оплатить интернет», «Купить продукты».
    case maintenance
    /// Повторяющееся: «Разобрать входящие», зарядка, планирование недели.
    case routine
    /// Пришло извне и ждёт реакции: «Ответить Ивану», «Перезвонить в банк».
    case incoming
    /// Разовое личное без цели: «Позвонить другу».
    case standalone

    /// Для карточки задачи — единственного места, где тип виден.
    var title: String {
        switch self {
        case .goal: return "Шаг к цели"
        case .obligation: return "Обязательство"
        case .maintenance: return "Быт и дела"
        case .routine: return "Рутина"
        case .incoming: return "Входящее"
        case .standalone: return "Разовое"
        }
    }

    /// Сколько обычно занимает такая задача, когда человек не сказал сам.
    /// Раньше любая задача без оценки занимала в плане 45 минут — и
    /// «Оплатить интернет», и «Подготовить релиз».
    var typicalMinutes: Int {
        switch self {
        case .goal: return 60
        case .obligation: return 30
        case .maintenance: return 30
        case .routine: return 30
        case .incoming: return 15
        case .standalone: return 30
        }
    }

    /// Сколько головы обычно нужно — сложность новой задачи, если человек
    /// её не назвал.
    var typicalDemand: CognitiveDemand {
        switch self {
        case .goal: return .deep
        case .obligation: return .normal
        case .maintenance, .routine, .incoming: return .light
        case .standalone: return .normal
        }
    }
}
