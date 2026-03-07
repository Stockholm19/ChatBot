import Foundation
import Vapor

public actor PollingHealthStore {
    public struct Snapshot: Sendable {
        public let startedAt: Date
        public let pollingTaskStartedAt: Date?
        public let lastSuccessfulPollAt: Date?
        public let lastErrorAt: Date?
        public let lastErrorMessage: String?
    }

    private let startedAt: Date
    private var pollingTaskStartedAt: Date?
    private var lastSuccessfulPollAt: Date?
    private var lastErrorAt: Date?
    private var lastErrorMessage: String?

    public init(now: Date = Date()) {
        self.startedAt = now
    }

    public func markPollingTaskStarted(at date: Date = Date()) {
        pollingTaskStartedAt = date
    }

    public func markSuccessfulPoll(at date: Date = Date()) {
        lastSuccessfulPollAt = date
        lastErrorAt = nil
        lastErrorMessage = nil
    }

    public func markPollError(_ message: String, at date: Date = Date()) {
        lastErrorAt = date
        lastErrorMessage = message
    }

    public func snapshot() -> Snapshot {
        Snapshot(
            startedAt: startedAt,
            pollingTaskStartedAt: pollingTaskStartedAt,
            lastSuccessfulPollAt: lastSuccessfulPollAt,
            lastErrorAt: lastErrorAt,
            lastErrorMessage: lastErrorMessage
        )
    }
}

private struct PollingHealthStoreKey: StorageKey {
    typealias Value = PollingHealthStore
}

extension Application {
    public var pollingHealthStore: PollingHealthStore {
        get {
            if let store = self.storage[PollingHealthStoreKey.self] {
                return store
            }
            let store = PollingHealthStore()
            self.storage[PollingHealthStoreKey.self] = store
            return store
        }
        set {
            self.storage[PollingHealthStoreKey.self] = newValue
        }
    }
}
