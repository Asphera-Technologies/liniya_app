import Testing
import Foundation
@testable import LineaCore

/// Долгоживущие документы хранятся как JSON. Когда в них появляется поле,
/// старая запись должна прочитаться — иначе обновление приложения молча
/// сбросит настройки и всю калибровку.
@Suite("Совместимость сохранённых документов")
struct DocumentMigrationTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    @Test("Профиль без новых полей читается с дефолтами")
    func userProfile() throws {
        // Так профиль выглядел до появления переключателя календаря.
        let old = """
        {"workdayStart":{"hour":9,"minute":0},"workdayEnd":{"hour":21,"minute":0},
         "quietHoursStart":{"hour":22,"minute":0},"quietHoursEnd":{"hour":8,"minute":0},
         "eveningCheckIn":{"hour":20,"minute":30},"sleepNeedSeconds":27000,
         "onboardingCompleted":true}
        """
        let profile = try decode(UserProfile.self, old)
        #expect(profile.onboardingCompleted)
        #expect(profile.sleepNeedSeconds == 27_000)
        #expect(profile.isCalendarEnabled == false)
        #expect(profile.workdayStart == TimeOfDay(hour: 9))
    }

    @Test("Совсем пустой документ не роняет чтение")
    func emptyDocuments() throws {
        #expect(try decode(UserProfile.self, "{}").workdayStart == UserProfile.default.workdayStart)
        #expect(try decode(NutritionProfile.self, "{}").mealWindows == NutritionProfile.defaultMealWindows)
        #expect(try decode(Calibration.self, "{}").reduceThreshold == Calibration.default.reduceThreshold)
    }

    @Test("Калибровка сохраняет выученное и добирает недостающее")
    func calibration() throws {
        let old = """
        {"energyBias":-0.05,"reduceThreshold":0.44,"ratingsCount":9}
        """
        let calibration = try decode(Calibration.self, old)
        #expect(calibration.energyBias == -0.05)
        #expect(calibration.reduceThreshold == 0.44)
        #expect(calibration.ratingsCount == 9)
        #expect(calibration.pushThreshold == Calibration.default.pushThreshold)
        #expect(calibration.changeLog.isEmpty)
    }

    @Test("Профиль питания без списка окон получает окно обеда")
    func nutritionProfile() throws {
        let profile = try decode(NutritionProfile.self, #"{"restrictions":["глютен"]}"#)
        #expect(profile.restrictions == ["глютен"])
        #expect(profile.mealWindows.count == 1)
        #expect(profile.mealWindows.first?.kind == .lunch)
    }

    @Test("Запись и чтение туда-обратно ничего не теряют")
    func roundTrip() throws {
        var profile = UserProfile(name: "Фёдор")
        profile.isCalendarEnabled = true
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        #expect(decoded == profile)
    }
}
