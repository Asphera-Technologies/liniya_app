import Testing
import Foundation
@testable import LineaCore

@Suite("Итог дня: чтение русской речи")
struct CheckInTextTests {

    private func words(_ text: String) -> [String] {
        RussianWords.tokens(text).map(\.normalized)
    }

    // MARK: Слова и части

    @Test("Слова: «ё» → «е», дробь остаётся числом, знаки делят предложения")
    func tokens() {
        #expect(words("Всё сделал за 2,5 часа!") == ["все", "сделал", "за", "2.5", "часа"])
        let pieces = RussianWords.pieces("Сделал отчёт. Потом — созвон")
        #expect(pieces.filter { $0 == .sentenceEnd }.count == 1)
        #expect(pieces.filter { $0 == .pause }.count == 1)
    }

    @Test("Основа слова переживает окончания и приставки")
    func stems() {
        #expect(RussianWords.stem("Презентация") == "презе")
        #expect(RussianWords.word("презентацию", matches: RussianWords.stem("презентация")))
        #expect(RussianWords.word("почту", matches: RussianWords.stem("почта")))
        #expect(RussianWords.word("потренировался", matches: RussianWords.stem("тренировка")))
        #expect(RussianWords.stem("зал") == "зал")
        // Короткая основа не цепляется за длинные слова.
        #expect(!RussianWords.word("планировал", matches: RussianWords.stem("план")))
    }

    @Test("Части предложения: союзы и запятые, «а» — противопоставление")
    func clauses() {
        let clauses = CheckInText.clauses("Сделал отчёт и презентацию, а спортзал не успел. Потом созвон.")
        #expect(clauses.map(\.words) == [["сделал", "отчет"], ["презентацию"], ["спортзал", "не", "успел"], ["созвон"]])
        #expect(clauses.map(\.link) == [.start, .continuation, .contrast, .start])
        #expect(clauses.map(\.sentence) == [0, 0, 0, 1])
    }

    // MARK: Статус

    @Test("Статус части: сделал, не успел, начал")
    func status() {
        #expect(CheckInText.status(of: words("закончил отчёт")) == .done)
        #expect(CheckInText.status(of: words("отчёт готов")) == .done)
        #expect(CheckInText.status(of: words("отчёт не успел")) == .notDone)
        #expect(CheckInText.status(of: words("спортзал перенёс на завтра")) == .notDone)
        #expect(CheckInText.status(of: words("начал отчёт")) == .partial)
        #expect(CheckInText.status(of: words("сделал не до конца")) == .partial)
        #expect(CheckInText.status(of: words("отчёт")) == nil)
    }

    // MARK: Длительности

    @Test("Длительности, как их говорят")
    func durations() {
        func minutes(_ text: String) -> [Int] { CheckInText.durations(in: words(text)).map(\.minutes) }
        #expect(minutes("работал 3 часа") == [180])
        #expect(minutes("работал часа три") == [180])
        #expect(minutes("полтора часа") == [90])
        #expect(minutes("два с половиной часа") == [150])
        #expect(minutes("час двадцать") == [80])
        #expect(minutes("два часа двадцать минут") == [140])
        #expect(minutes("два часа двадцать") == [140])
        #expect(minutes("минут сорок") == [40])
        #expect(minutes("минут на сорок") == [40])
        #expect(minutes("полчаса") == [30])
        #expect(minutes("работал час") == [60])
        #expect(minutes("двадцать пять минут") == [25])
        #expect(minutes("2.5 часа") == [150])
    }

    @Test("Время на часах — не длительность")
    func clockTime() {
        #expect(CheckInText.durations(in: words("созвон в два часа")).isEmpty)
        #expect(CheckInText.durations(in: words("лёг в час ночи")).isEmpty)
        #expect(CheckInText.durations(in: words("к трём часам")).isEmpty)
    }

    // MARK: Оценка дня

    @Test("Оценка дня по словам, с «не» и смягчениями")
    func rating() {
        #expect(CheckInText.rating(words("день тяжёлый, очень устал")) == .hard)
        #expect(CheckInText.rating(words("отличный продуктивный день")) == .great)
        #expect(CheckInText.rating(words("нормальный день")) == .ok)
        #expect(CheckInText.rating(words("немного устал, а так нормально")) == .ok)
        #expect(CheckInText.rating(words("устал, но доволен")) == .ok)
        #expect(CheckInText.rating(words("сделал отчёт")) == nil)
    }

    @Test("Силы по словам")
    func energy() {
        #expect(CheckInText.energy(words("к вечеру нет сил")) == .low)
        #expect(CheckInText.energy(words("чувствую себя бодрым и полон сил")) == .high)
        #expect(CheckInText.energy(words("немного устал")) == .medium)
        #expect(CheckInText.energy(words("сделал отчёт")) == nil)
    }
}

@Suite("Итог дня: нарезка записи для модели на телефоне")
struct SpeechChunkerTests {
    private let second = 16_000

    @Test("Соседние фразы склеиваются в кусок не длиннее предела, с паузами")
    func mergesWithinLimit() {
        let ranges = [0..<(5 * second), (6 * second)..<(12 * second), (13 * second)..<(19 * second), (20 * second)..<(30 * second)]
        let chunks = SpeechChunker.chunks(speech: ranges, total: 40 * second, limit: 20 * second, padding: 0)
        #expect(chunks == [0..<(19 * second), (20 * second)..<(30 * second)])
    }

    @Test("Поля по краям не выходят за запись")
    func padding() {
        let chunks = SpeechChunker.chunks(speech: [100..<(3 * second)], total: 3 * second + 10, limit: 20 * second, padding: second / 5)
        #expect(chunks == [0..<(3 * second + 10)])
    }

    @Test("Сплошная речь длиннее предела режется жёстко")
    func hardSplit() {
        let chunks = SpeechChunker.chunks(speech: [0..<(50 * second)], total: 50 * second, limit: 20 * second, padding: 0)
        #expect(chunks == [0..<(20 * second), (20 * second)..<(40 * second), (40 * second)..<(50 * second)])
        #expect(chunks.allSatisfy { $0.count <= 20 * second })
    }

    @Test("Тишина — пусто")
    func empty() {
        #expect(SpeechChunker.chunks(speech: [], total: 10 * second, limit: 20 * second, padding: 0).isEmpty)
    }
}
