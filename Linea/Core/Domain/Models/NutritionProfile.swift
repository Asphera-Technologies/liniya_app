//
//  NutritionProfile.swift
//  Linea
//
//  Minimal nutrition model for v1: what the user can / cannot eat, condition
//  tags (never interpreted medically), and meal windows. Meal windows become
//  commitments in the plan; the profile constrains meal recommendations.
//

import Foundation

nonisolated enum MealKind: String, Codable, Hashable, Sendable, CaseIterable {
    case breakfast, lunch, dinner, snack

    var title: String {
        switch self {
        case .breakfast: return "Завтрак"
        case .lunch: return "Обед"
        case .dinner: return "Ужин"
        case .snack: return "Перекус"
        }
    }
}

nonisolated struct MealWindow: Codable, Hashable, Sendable, Identifiable {
    var kind: MealKind
    var start: TimeOfDay
    var durationMinutes: Int

    init(kind: MealKind, start: TimeOfDay, durationMinutes: Int = 40) {
        self.kind = kind
        self.start = start
        self.durationMinutes = durationMinutes
    }

    var id: String { "\(kind.rawValue)-\(start.hour):\(start.minute)" }
}

nonisolated struct NutritionProfile: Codable, Hashable, Sendable {
    static let schemaVersion = 1

    /// Free-form diet name («вегетарианство», «без глютена», «кето»…).
    var dietType: String?
    /// Restrictions as tags (e.g. "gluten", "lactose", "sugar").
    var restrictions: [String]
    var excludedProducts: [String]
    var preferredProducts: [String]
    /// Condition tags entered by the user; used only as filters, never interpreted.
    var conditions: [String]
    var mealWindows: [MealWindow]

    init(
        dietType: String? = nil,
        restrictions: [String] = [],
        excludedProducts: [String] = [],
        preferredProducts: [String] = [],
        conditions: [String] = [],
        mealWindows: [MealWindow] = NutritionProfile.defaultMealWindows
    ) {
        self.dietType = dietType
        self.restrictions = restrictions
        self.excludedProducts = excludedProducts
        self.preferredProducts = preferredProducts
        self.conditions = conditions
        self.mealWindows = mealWindows
    }

    /// Lenient decoding, like `UserProfile`: an added field must not wipe a
    /// profile written by an older build.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = NutritionProfile()
        dietType = try container.decodeIfPresent(String.self, forKey: .dietType)
        restrictions = try container.decodeIfPresent([String].self, forKey: .restrictions) ?? fallback.restrictions
        excludedProducts = try container.decodeIfPresent([String].self, forKey: .excludedProducts) ?? fallback.excludedProducts
        preferredProducts = try container.decodeIfPresent([String].self, forKey: .preferredProducts) ?? fallback.preferredProducts
        conditions = try container.decodeIfPresent([String].self, forKey: .conditions) ?? fallback.conditions
        mealWindows = try container.decodeIfPresent([MealWindow].self, forKey: .mealWindows) ?? fallback.mealWindows
    }

    static let defaultMealWindows: [MealWindow] = [
        MealWindow(kind: .lunch, start: TimeOfDay(hour: 13), durationMinutes: 40),
    ]

    var hasConstraints: Bool {
        dietType != nil || !restrictions.isEmpty || !excludedProducts.isEmpty || !conditions.isEmpty
    }
}

/// A meal the user marked as eaten («Поел»).
nonisolated struct MealLog: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var at: Date
    var kind: MealKind
    var note: String?

    init(id: UUID = UUID(), at: Date, kind: MealKind, note: String? = nil) {
        self.id = id
        self.at = at
        self.kind = kind
        self.note = note
    }
}
