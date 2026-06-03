import Foundation
enum EquatableError: Swift.Error, Equatable {
    static func == (lhs: EquatableError, rhs: EquatableError) -> Bool {
        lhs.description == rhs.description
    }
    var description: String {
        "\(self)"
    }
    case noData
    case wrongData(Data)
    case unknown(Error)
}
enum Loadable<T: Equatable & Sendable>: Equatable, Sendable {
    case notRequested
    case loading
    case loaded(T)
    case failed(EquatableError)
}

// MARK: - Convenience

extension Loadable {
    var notRequested: Bool {
        guard case .notRequested = self else { return false }
        return true
    }

    var loading: Bool {
        guard case .loading = self else { return false }
        return true
    }

    var loaded: Bool {
        guard case .loaded = self else { return false }
        return true
    }

    var failed: Bool {
        guard case .failed = self else { return false }
        return true
    }

    var value: T? {
        guard case let .loaded(value) = self else { return nil }
        return value
    }

    var error: Error? {
        guard case .failed(.noData) = self else { return nil }
        return self.error
    }

    func get() throws -> T? {
        switch self {
        case .loading, .notRequested:
            return nil
        case let .loaded(value):
            return value
        case let .failed(.unknown(error)):
            throw error
        case .failed(.noData):
            throw EquatableError.noData
        case .failed(.wrongData):
            return nil
        }
    }
}
