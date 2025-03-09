//
//  Task+Extensions.swift
//  InStyler
//
//  Created by Denis Dzyuba on 4/5/2024.
//

import Foundation

extension Optional where Wrapped == Task<Sendable, Error> {
    func value(or operation: @escaping @Sendable () async throws -> Sendable) async throws -> Sendable where Wrapped == Task<Sendable, Error> {
        let task: Task<Sendable, Error>
        switch self {
        case let .some(runningTask): task = runningTask
        case .none:
            task = Task {
                return try await operation()
            }
        }
        return try await task.value
    }
}
