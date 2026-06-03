import Foundation
import Synchronization
import os

public final class SyncStorage<Value: Sendable>: Sendable {
    private let _value: Mutex<Value>

    public init(_ initial: Value) {
        _value = Mutex(initial)
    }

    public func get() -> Value { _value.withLock { $0 } }
    public func set(_ v: Value) { _value.withLock { $0 = v } }
}

// MARK: - Optional

public final class OptionalSyncStorage<Value: Sendable>: Sendable {
    private let lock: Mutex<Value?>

    public init(_ initial: Value? = nil) {
        lock = Mutex(initial)
    }

    public func get() -> Value? { lock.withLock { $0 } }
    public func set(_ v: Value?) { lock.withLock { $0 = v } }
}
