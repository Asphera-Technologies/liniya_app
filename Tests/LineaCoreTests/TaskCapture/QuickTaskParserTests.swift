import Testing
import Foundation
@testable import LineaCore

/// Быстрый ввод одной строкой. Время — среда 9 сентября 2026, 08:00 по Москве
/// (`WowFixture`): «завтра» — четверг 10-го, «в пятницу» — 11-го.
@Suite("Быстрый ввод: разбор строки")
struct QuickTaskParserTests {
    private let parser = QuickTaskParser()
    private let time = WowFixture.morning

    private func parse(_ text: String, at time: TimeContext? = nil, goals: [LineaGoal] = []) -> QuickTaskParse {
        parser.parse(text, goals: goals, profile: WowFixture.profile, time: time ?? self.time)
    }

    private func day(_ offset: Int) -> TaskDay {
        .date(WowFixture.calendar.startOfDay(for: WowFixture.moment(12, 0, dayOffset: offset)))
    }

    // MARK: Название

    @Test("Только название: ничего не распознано, название как написано")
    func titleOnly() {
        let result = parse("Оплатить интернет")
        #expect(result.title == "Оплатить интернет")
        #expect(result.day == nil)
        #expect(result.minutes == nil)
        #expect(result.priority == nil)
        #expect(result.deadline == nil)
        #expect(result.recognized.isEmpty)
    }

    @Test("Пример из задачи: день, длительность и приоритет уходят из названия")
    func fullPhrase() {
        let result = parse("Купить продукты завтра на полчаса, важно")
        #expect(result.title == "Купить продукты")
        #expect(result.day == .tomorrow)
        #expect(result.minutes == 30)
        #expect(result.priority == .important)
        #expect(result.recognized.map(\.part) == [.priority, .day, .duration])
    }

    @Test("Знаки внутри названия остаются, первая буква заглавная")
    func titleKeepsPunctuation() {
        #expect(parse("Купить молоко, хлеб и яйца завтра").title == "Купить молоко, хлеб и яйца")
        #expect(parse("сегодня позвонить маме").title == "Позвонить маме")
        // Всё распознано — название не теряется.
        let only = parse("Завтра")
        #expect(only.title == "Завтра")
        #expect(only.day == .tomorrow)
    }

    // MARK: День

    @Test("Дни словами: сегодня, послезавтра, дни недели, «эта» и «следующая»")
    func days() {
        #expect(parse("Отчёт сегодня").day == .today)
        #expect(parse("Позвонить маме послезавтра").day == day(2))
        let bank = parse("Сходить в банк в пятницу")
        #expect(bank.day == day(2))
        #expect(bank.title == "Сходить в банк")
        #expect(parse("Встреча в понедельник").day == day(5))
        // Среда сегодня: «в среду» — следующая, «в эту среду» — сегодня.
        #expect(parse("Отчёт в среду").day == day(7))
        #expect(parse("Отчёт в эту среду").day == .today)
        #expect(parse("Ретро в следующую пятницу").day == day(9))
        #expect(parse("Отчёт пятница").day == day(2))
    }

    @Test("«На неделе», следующая неделя, выходные, «через»")
    func relativeDays() {
        let week = parse("Подготовить релиз на неделе")
        #expect(week.day == .thisWeek)
        #expect(week.title == "Подготовить релиз")
        #expect(parse("Спланировать отпуск на следующей неделе").day == day(5))
        #expect(parse("Разобрать шкаф на выходных").day == day(3))
        let doctor = parse("Записаться к врачу через 3 дня")
        #expect(doctor.day == day(3))
        #expect(doctor.title == "Записаться к врачу")
        #expect(parse("Проверить отчёт через неделю").day == day(7))
        // «Через день» неоднозначно — остаётся в названии.
        #expect(parse("Полить цветы через день").day == nil)
    }

    @Test("Даты: «15 октября», «15.10», прошедшее число — в следующем году")
    func dates() {
        #expect(parse("Продлить страховку 15 октября").day == day(36))
        #expect(parse("Сдать документы 15.10").day == day(36))
        #expect(parse("Сдать документы на 15.10").title == "Сдать документы")
        let next = parse("Купить подарок 1 сентября")
        let expected = WowFixture.calendar.date(from: DateComponents(year: 2027, month: 9, day: 1))!
        #expect(next.day == .date(expected))
        // Не дата: «2 главы», «2 кг».
        #expect(parse("Прочитать 2 главы").day == nil)
        #expect(parse("Купить 2 кг яблок").title == "Купить 2 кг яблок")
    }

    // MARK: Срок

    @Test("Срок: «до 18:00», «к пятнице», «до пятницы 15:00», «до 25 числа»")
    func deadlines() {
        let send = parse("Отправить документ клиенту до 18:00")
        #expect(send.title == "Отправить документ клиенту")
        #expect(send.deadline == WowFixture.moment(18))
        #expect(send.day == nil)
        #expect(parse("Отчёт к пятнице").deadline == WowFixture.moment(21, 0, dayOffset: 2))
        #expect(parse("Отчёт до пятницы 15:00").deadline == WowFixture.moment(15, 0, dayOffset: 2))
        #expect(parse("Оплатить квартиру до 25 числа").deadline == WowFixture.moment(21, 0, dayOffset: 16))
        #expect(parse("Сдать отчёт до вечера").deadline == WowFixture.moment(18))
        let named = parse("Презентация, дедлайн завтра")
        #expect(named.title == "Презентация")
        #expect(named.deadline == WowFixture.moment(21, 0, dayOffset: 1))
    }

    @Test("«До конца недели» — то же, что «на неделе»; «до 7» — вечер")
    func deadlineWords() {
        let week = parse("Договор до конца недели")
        #expect(week.day == .thisWeek)
        #expect(week.deadline == nil)
        #expect(week.title == "Договор")
        #expect(parse("Позвонить до 7").deadline == WowFixture.moment(19))
    }

    @Test("Время срока прошло — значит, завтра; у задачи на день — в тот день")
    func deadlineRollsOver() {
        let late = parse("Позвонить до 10:00", at: WowFixture.time(20))
        #expect(late.deadline == WowFixture.moment(10, 0, dayOffset: 1))
        let friday = parse("Отчёт в пятницу до 12:00")
        #expect(friday.day == day(2))
        #expect(friday.deadline == WowFixture.moment(12, 0, dayOffset: 2))
    }

    @Test("Слова «к», «до» без срока остаются в названии")
    func notDeadlines() {
        #expect(parse("Купить продукты к ужину").title == "Купить продукты к ужину")
        #expect(parse("Дойти до дома").deadline == nil)
        #expect(parse("Ответить на письма").title == "Ответить на письма")
    }

    // MARK: Время начала

    @Test("Время начала: «в 15:00», «в 7 вечера», «в 9 утра», «в 10», голое «15:00»")
    func startTimes() {
        let call = parse("Созвон с командой в 15:00")
        #expect(call.startTime == TimeOfDay(hour: 15))
        #expect(call.title == "Созвон с командой")
        #expect(parse("Позвонить маме в 7 вечера").startTime == TimeOfDay(hour: 19))
        let morning = parse("Тренировка в 9 утра завтра")
        #expect(morning.startTime == TimeOfDay(hour: 9))
        #expect(morning.day == .tomorrow)
        #expect(morning.title == "Тренировка")
        #expect(parse("Встреча в 10").startTime == TimeOfDay(hour: 10))
        #expect(parse("Созвон 16:30").startTime == TimeOfDay(hour: 16, minute: 30))
        // До начала рабочего дня — скорее вечер.
        #expect(parse("Пробежка в 7").startTime == TimeOfDay(hour: 19))
        #expect(parse("Позвонить в 3 часа дня").startTime == TimeOfDay(hour: 15))
    }

    @Test("Не время: «в 2 банка», «на 2 часа» — длительность")
    func notStartTimes() {
        let banks = parse("Позвонить в 2 банка")
        #expect(banks.startTime == nil)
        #expect(banks.title == "Позвонить в 2 банка")
        let workout = parse("Тренировка на 2 часа")
        #expect(workout.startTime == nil)
        #expect(workout.minutes == 120)
        #expect(workout.title == "Тренировка")
    }

    // MARK: Длительность

    @Test("Длительности: минуты, полтора часа, «за час», «около часа»")
    func durations() {
        let inbox = parse("Разобрать входящие 15 минут")
        #expect(inbox.minutes == 15)
        #expect(inbox.title == "Разобрать входящие")
        #expect(parse("Подготовить стратегию, полтора часа").minutes == 90)
        let post = parse("Написать пост за час")
        #expect(post.minutes == 60)
        #expect(post.title == "Написать пост")
        #expect(parse("Почитать около часа").minutes == 60)
        #expect(parse("Созвон 30 мин").minutes == 30)
        #expect(parse("Отчёт 1,5 часа").minutes == 90)
    }

    @Test("«Через 2 часа» — не длительность; «на 3 недели» — не про задачу")
    func notDurations() {
        let later = parse("Позвонить через 2 часа")
        #expect(later.minutes == nil)
        #expect(later.title == "Позвонить через 2 часа")
        #expect(parse("Купить продукты на неделю").title == "Купить продукты на неделю")
    }

    // MARK: Приоритет

    @Test("Приоритет словами: срочно, не срочно, когда-нибудь, «!!»")
    func priorities() {
        let tax = parse("Оплатить налог срочно")
        #expect(tax.priority == .important)
        #expect(tax.title == "Оплатить налог")
        let photos = parse("Разобрать фото не срочно")
        #expect(photos.priority == .low)
        #expect(photos.title == "Разобрать фото")
        let book = parse("Купить книгу когда-нибудь")
        #expect(book.priority == .low)
        #expect(book.day == .someday)
        #expect(parse("Сверить счета, высокий приоритет").priority == .important)
        #expect(parse("Сверить счета с низким приоритетом").priority == .low)
        let bang = parse("Отчёт!!")
        #expect(bang.priority == .important)
        #expect(bang.title == "Отчёт")
        // Один «!» — просто знак.
        #expect(parse("Отчёт!").priority == nil)
    }

    // MARK: Надиктованное

    @Test("Служебное в начале надиктованной фразы уходит, глагол задачи остаётся")
    func fillers() {
        let bread = parse("Добавь задачу купить хлеб завтра.")
        #expect(bread.title == "Купить хлеб")
        #expect(bread.day == .tomorrow)
        #expect(parse("Ну, надо позвонить маме").title == "Позвонить маме")
        #expect(parse("Напомни мне оплатить интернет").title == "Оплатить интернет")
        #expect(parse("Задача: купить хлеб").title == "Купить хлеб")
        #expect(parse("Записать видео для канала").title == "Записать видео для канала")
        #expect(parse("Так держать форму").title == "Так держать форму")
    }

    @Test("Надиктованная задача целиком: всё по местам")
    func dictatedTask() {
        let result = parse("Добавь задачу подготовить отчёт для клиента завтра в 10 утра на полтора часа, важно.")
        #expect(result.title == "Подготовить отчёт для клиента")
        #expect(result.day == .tomorrow)
        #expect(result.startTime == TimeOfDay(hour: 10))
        #expect(result.minutes == 90)
        #expect(result.priority == .important)
    }

    // MARK: Цель и сложность

    @Test("«Для цели …» связывает с активной целью, даже если имя распознано по-русски")
    func explicitGoal() {
        let goals = WowFixture.goals
        let release = parse("Подготовить релиз для цели запустить линию", goals: goals)
        #expect(release.goalID == WowFixture.goalMVP)
        #expect(release.title == "Подготовить релиз")
        let label = parse("Цель: MVP, написать лендинг", goals: goals)
        #expect(label.goalID == WowFixture.goalMVP)
        #expect(label.title == "Написать лендинг")
        // Такой цели нет — слова остаются в названии.
        let missing = parse("Подготовить релиз для цели похудеть", goals: goals)
        #expect(missing.goalID == nil)
        #expect(missing.title == "Подготовить релиз для цели похудеть")
        #expect(parse("Поставить цель на год", goals: goals).title == "Поставить цель на год")
    }

    @Test("Сложность — подсказкой, слова в названии остаются")
    func demand() {
        let deep = parse("Сложная презентация")
        #expect(deep.demand == .deep)
        #expect(deep.title == "Сложная презентация")
        #expect(parse("Быстро ответить Пете").demand == .light)
        #expect(parse("Купить хлеб").demand == nil)
    }

    // MARK: Конец недели

    @Test("«На неделе»: до воскресенья этой недели, в выходные — следующей")
    func endOfWeek() {
        func end(_ offset: Int) -> Date {
            TaskDay.endOfWeek(time: WowFixture.time(10, 0, dayOffset: offset), profile: WowFixture.profile)
        }
        #expect(end(0) == WowFixture.moment(21, 0, dayOffset: 4))   // ср → вс 13-го
        #expect(end(3) == WowFixture.moment(21, 0, dayOffset: 11))  // сб → вс 20-го
        #expect(end(4) == WowFixture.moment(21, 0, dayOffset: 11))  // вс → вс 20-го
        #expect(end(5) == WowFixture.moment(21, 0, dayOffset: 11))  // пн → вс 20-го
        #expect(TaskDay.nextMonday(time: time) == WowFixture.calendar.startOfDay(for: WowFixture.moment(12, 0, dayOffset: 5)))
    }
}
