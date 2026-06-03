import Foundation
public actor AsyncStorage<Value: Sendable> {
    private var value: Value

    public init(_ initial: Value) {
        value = initial
    }

    public func get() -> Value { value }
    public func set(_ v: Value) { value = v }
}

// MARK: - Optional

public actor OptionalAsyncStorage<Value: Sendable> {
    private var value: Value?

    public init(_ initial: Value? = nil) {
        value = initial
    }

    public func get() -> Value? { value }
    public func set(_ v: Value?) { value = v }
}
