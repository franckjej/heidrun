import Foundation
public struct AnySendableWrapper: @unchecked Sendable {
    public let value: Any

    public init(_ initial: Any) {
        value = initial
    }
}

// MARK: - Optional

public struct OptionalAnySendableWrapper: @unchecked Sendable {
    public let value: Any?

    public init(_ initial: Any? = nil) {
        value = initial
    }
}
