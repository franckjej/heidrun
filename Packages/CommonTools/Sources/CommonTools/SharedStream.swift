import Foundation

public actor SharedStream<T: Sendable> {
    public init() { }

    private var continuations: [UUID: AsyncStream<T>.Continuation] = [:]

    public func create(with value: T? = nil) -> AsyncStream<T> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }

                Task { await self.removeContinuation(for: id) }
            }
            if let value {
                continuation.yield(value)
            }
        }
    }

    func yield(_ value: T) {
        for continuation in continuations.values {
            continuation.yield(value)
        }
    }

    private func removeContinuation(for id: UUID) {
        continuations[id]?.finish()
        continuations.removeValue(forKey: id)
    }
}
