//
//  TaskRepository.swift
//  Linea
//
//  The task persistence boundary. Feature UI and use cases depend on this
//  protocol, never on SwiftData. Methods are async so a future remote
//  repository (and a sync service coordinating local + remote) can adopt the
//  same interface without any change to the Plan UI or the intelligence core.
//
//  The protocol is main-actor isolated (the project's default), because that is
//  where its implementations genuinely live: SwiftData's `mainContext`. Marking
//  it `nonisolated` would make the requirements nonisolated and cut the
//  implementations off from their own context.
//

import Foundation

protocol TaskRepository {
    func all() async throws -> [LineaTask]
    func add(_ task: LineaTask) async throws
    func update(_ task: LineaTask) async throws
    func delete(id: UUID) async throws
}
