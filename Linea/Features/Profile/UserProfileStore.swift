//
//  UserProfileStore.swift
//  Linea
//
//  View-facing state for the user profile: the working day, quiet hours, when
//  to ask how the day went, and the target sleep used before a personal
//  baseline exists. These are not settings for their own sake — they define
//  «доступное время сегодня», so the plan changes the moment they change.
//

import Foundation
import Observation

@Observable
@MainActor
final class UserProfileStore {
    private let repository: UserProfileRepository

    private(set) var profile: UserProfile = .default
    private(set) var errorMessage: String?

    /// Called after every change so the day plan can be recomputed.
    var onPlanInputsChanged: (@MainActor () async -> Void)?

    init(repository: UserProfileRepository) {
        self.repository = repository
    }

    func load() async {
        do {
            profile = try await repository.load()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ profile: UserProfile) async {
        do {
            try await repository.save(profile)
            self.profile = profile
            await onPlanInputsChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
