//
//  NutritionStore+Preview.swift
//  Linea
//
//  Preview-only factories for the stores that back Nutrition and Profile.
//  Kept out of the stores themselves so those stay free of any SwiftData
//  import, which is what lets the UI depend on protocols only.
//

import Foundation
import SwiftData

extension NutritionStore {
    @MainActor
    static var preview: NutritionStore {
        // Превью не ходит в сеть: каталог не подключён.
        NutritionStore(repository: LocalNutritionRepository(context: PreviewContainer.shared.mainContext))
    }
}

extension UserProfileStore {
    @MainActor
    static var preview: UserProfileStore {
        UserProfileStore(repository: LocalUserProfileRepository(context: PreviewContainer.shared.mainContext))
    }
}

/// One in-memory container shared by every preview (no disk writes).
enum PreviewContainer {
    @MainActor
    static let shared: ModelContainer = {
        try! ModelContainer(
            for: Schema(LineaSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }()
}
