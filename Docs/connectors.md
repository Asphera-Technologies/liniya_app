# Как добавить коннектор

Коннектор — это новый источник данных для Linea: календарь, питание,
локация, экранное время, почта, ещё один носимый девайс. Смысл архитектуры в
том, что подключение источника **не требует правок ядра**: ни доменной
модели, ни движков, ни экранов.

## Четыре точки расширения

| Что нужно | Протокол | Где объявлен |
|---|---|---|
| Дать новые данные | `ContextProvider` | `Core/Domain/Protocols/ContextProvider.swift` |
| Повлиять на состояние человека | `StateAnalyzer` | `Core/Domain/Protocols/ContextEngineHooks.swift` |
| Повлиять на план и советы | `PlanRule` | там же |
| Добавить новый повод написать | `NudgeRule` | там же |

Регистрируются они в одном месте — composition root приложения. Движки
подписаны на **виды сигналов** (`SignalKind`), а не на конкретные
провайдеры, поэтому другой источник с теми же видами подхватывается сам.

## Шаг 1. Решить, какие сигналы вы даёте

Если ваши данные ложатся на существующие виды — ничего объявлять не надо.
Самый частый случай: **всё, что занимает время**, это `SignalKind.commitment`
(встреча, окно еды, тренировка, поездка). Планировщик сам вычтет их из
свободных окон, а нудж посчитает «до следующего обязательства осталось …».

Если нужен свой вид — объявите его **в своём файле**, не трогая ядро:

```swift
nonisolated extension SignalKind {
    static let mealLogged: SignalKind = "nutrition.mealLogged"
}
```

Договорённости по именам: `<домен>.<сущность>.<метрика>`, единицы —
канонические (секунды, миллисекунды, bpm, ккал, count).

## Шаг 2. Написать провайдер

Foundation-only часть кладите в `Linea/Core/Connectors/<Name>/` — тогда её
можно тестировать на Linux. Часть, которой нужны Apple-фреймворки
(EventKit, HealthKit, SwiftData), — в `Linea/Data/Providers/<Name>/`.

```swift
import EventKit

nonisolated final class CalendarContextProvider: ContextProvider {
    let id: ProviderID = "calendar"
    let displayName = "Календарь"
    let provides: Set<SignalKind> = [.commitment]

    private nonisolated(unsafe) let store = EKEventStore()

    func fetchContext(_ request: ContextRequest) async throws -> ProviderFetchResult {
        guard try await store.requestFullAccessToEvents() else { throw ProviderError.unauthorized }
        let predicate = store.predicateForEvents(withStart: request.window.start,
                                                 end: request.window.end,
                                                 calendars: nil)
        let signals = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { event in
                ContextSignal(
                    kind: .commitment,
                    value: .interval(nil),
                    start: event.startDate,
                    end: event.endDate,
                    source: id,
                    attributes: [
                        SignalAttribute.label: event.title ?? "Событие",
                        SignalAttribute.commitmentKind: CommitmentKind.meeting.rawValue,
                        SignalAttribute.eventID: event.eventIdentifier ?? "",
                    ]
                )
            }
        return ProviderFetchResult(signals: signals, status: signals.isEmpty ? .noData : .ready)
    }
}
```

Правила:

- **Не читайте текущее время сами.** Всё нужное есть в `request.time`
  (`TimeContext`) и `request.window`.
- **Бросать ошибку можно.** `ContextEngine` поймает её, превратит в
  `ProviderStatus`, и план соберётся без вас. Отдельно есть таймаут.
- **Не интерпретируйте данные.** Провайдер только переводит источник в
  сигналы; смысл им придают анализаторы и правила.
- `provides` — для экрана «Подключения» и диагностики.

## Шаг 3. При необходимости — повлиять на состояние

Если источник говорит что-то о ресурсе человека, добавьте компонент
состояния. Формулу свёртки менять не надо: вес компонента задаётся в
`EngineConfig.componentWeights`.

```swift
nonisolated struct NutritionFuelAnalyzer: StateAnalyzer {
    let kind: StateComponentKind = .fuel

    func analyze(_ input: StateInput) -> StateComponent? {
        // nil = «мне нечего сказать», а не «всё хорошо»
        ...
        return StateComponent(kind: kind, score: score, confidence: 0.6, facts: facts)
    }
}
```

Компонент с низкой уверенностью сам по себе почти не двигает результат:
свёртка тянет энергию к нейтральным 0.5, а не к значению компонента.

## Шаг 4. При необходимости — повлиять на план

```swift
nonisolated struct NutritionRule: PlanRule {
    let id = "nutrition"
    let renderer: any TextRenderer

    func apply(to plan: inout DayPlan, context: PlanningContext) -> [Recommendation] {
        // можно добавить блок в план и/или вернуть рекомендации
    }
}
```

Правило должно быть детерминированным: одинаковый вход — одинаковый выход.
Тексты не пишите руками — соберите факты и отдайте их `TextRenderer`.

## Шаг 5. Зарегистрировать

Одна-три строки в composition root:

```swift
providers.append(CalendarContextProvider())
analyzers.append(NutritionFuelAnalyzer())
planRules.append(NutritionRule(renderer: explainer))
```

## Шаг 6. Разрешения и настройки таргета (только на Mac)

Например, для календаря — `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription`
в настройках таргета. Для уведомлений разрешение запрашивается в рантайме.

## Шаг 7. Тесты

Логику коннектора проверяйте в Docker (`Scripts/test-core.sh`), подменяя
источник фейковым провайдером из `Tests/LineaCoreTests/Fakes`:

```swift
let engine = ContextEngine(providers: [FakeContextProvider(signals: [
    ContextSignal(kind: .commitment, value: .interval(nil),
                  start: WowFixture.moment(10), end: WowFixture.moment(11),
                  source: "calendar",
                  attributes: [SignalAttribute.label: "Встреча"])
])])
```

Сам провайдер (EventKit/HealthKit) проверяется только на устройстве —
внесите его в чек-лист `Docs/roadmap.md`.

## Чего делать не нужно

- **Не добавляйте поля в доменные модели** ради своего источника. Всё, что
  специфично, живёт в `ContextSignal.attributes` и в вашем анализаторе.
- **Не добавляйте слагаемые в формулу приоритета.** Пять компонент
  (`urgency`, `importance`, `goalAlignment`, `energyFit`, `durationFit`)
  фиксированы; влияйте через состояние или правило.
- **Не превращайте задачи и цели в сигналы.** Это предмет решения, они уже
  лежат в снапшоте типизированно.
- **Не читайте `Date()` в ядре.** Тесты станут невоспроизводимыми.
