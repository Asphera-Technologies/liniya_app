import Testing
import Foundation
@testable import LineaCore

@Suite("Коннектор питания")
struct NutritionConnectorTests {
    private let time = WowFixture.morning

    private func request(_ time: TimeContext) -> ContextRequest {
        ContextRequest(day: time.dayInterval(containing: time.today), time: time)
    }

    @Test("Окна еды становятся занятым временем")
    func mealWindowsBecomeCommitments() async throws {
        let provider = NutritionContextProvider(profile: WowFixture.nutrition, meals: [])
        let result = try await provider.fetchContext(request(time))
        let lunch = try #require(result.signals.first { $0.kind == .commitment })
        #expect(lunch.start == WowFixture.moment(13))
        #expect(lunch.end == WowFixture.moment(13, 40))
        #expect(lunch.attributes[SignalAttribute.label] == "Обед")
        #expect(lunch.attributes[SignalAttribute.commitmentKind] == CommitmentKind.meal.rawValue)
        #expect(result.status == .ready)
    }

    @Test("Отметка «Поел» становится сигналом")
    func mealLogged() async throws {
        let meal = MealLog(at: WowFixture.moment(13, 10), kind: .lunch)
        let provider = NutritionContextProvider(profile: WowFixture.nutrition, meals: [meal])
        let result = try await provider.fetchContext(request(WowFixture.afternoon))
        #expect(result.signals.contains { $0.kind == .mealLogged })
    }

    @Test("Без профиля и отметок источник честно говорит, что данных нет")
    func noData() async throws {
        let result = try await NutritionContextProvider(profile: nil, meals: []).fetchContext(request(time))
        #expect(result.status == .noData)
        #expect(result.signals.isEmpty)
    }

    @Test("Продукты берутся из «подходит» минус «не подходит»")
    func products() {
        var profile = WowFixture.nutrition
        profile.excludedProducts = ["Курица"]
        #expect(NutritionRule.products(profile) == ["овсянка", "овощи", "рыба"])
    }

    @Test("Топливо падает по часам без еды")
    func fuelComponent() {
        let analyzer = NutritionFuelAnalyzer()
        // Поел в 9:30, сейчас 14:30 → 5 часов, из них 2 сверх сытости.
        var snapshot = WowFixture.snapshot(at: WowFixture.afternoon)
        snapshot.meals = [MealLog(at: WowFixture.moment(9, 30), kind: .breakfast)]
        let input = StateInput(snapshot: snapshot, baselines: nil, history: [], time: WowFixture.afternoon)
        let component = analyzer.analyze(input)
        #expect(component != nil)
        #expect(abs((component?.score ?? 0) - 0.5) < 1e-9)
        #expect(component?.confidence == 0.6)
    }

    @Test("Недавняя еда — полный бак")
    func fuelAfterMeal() {
        var snapshot = WowFixture.snapshot(at: WowFixture.afternoon)
        snapshot.meals = [MealLog(at: WowFixture.moment(13, 30), kind: .lunch)]
        let input = StateInput(snapshot: snapshot, baselines: nil, history: [], time: WowFixture.afternoon)
        #expect(NutritionFuelAnalyzer().analyze(input)?.score == 1)
    }

    @Test("Утром до первого окна еды компонент молчит")
    func fuelSilentInTheMorning() {
        let snapshot = WowFixture.snapshot(at: WowFixture.morning)
        let input = StateInput(snapshot: snapshot, baselines: nil, history: [], time: WowFixture.morning)
        #expect(NutritionFuelAnalyzer().analyze(input) == nil)
    }
}
