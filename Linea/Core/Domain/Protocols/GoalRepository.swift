//
//  GoalRepository.swift
//  Linea
//
//  The goal persistence boundary. Same design as `TaskRepository`: an async
//  protocol the UI depends on, implemented by a SwiftData-backed local
//  repository in Data/Repositories.
//

import Foundation

protocol GoalRepository: Sendable {
    func all() async throws -> [LineaGoal]
    func add(_ goal: LineaGoal) async throws
    func update(_ goal: LineaGoal) async throws
    func delete(id: UUID) async throws
}
