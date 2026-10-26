import Foundation
import Observation
import Synchronization

/// User preference for the surface a threaded server opens on.
public enum NewsDefaultSurface: String, CaseIterable, Sendable {
    /// Threaded, unless only the board has content.
    case automatic
    case threaded
    case board

    /// Mirrors `AppStorageKeys.newsDefaultSurface`.
    public static let storageKey = "Heidrun.newsDefaultSurface"
    /// Mirrors `AppStorageKeys.newsAutoDownloadBoth`.
    public static let autoDownloadStorageKey = "Heidrun.newsAutoDownloadBoth"
}

extension NewsSurface {
    /// Surface to open on first load. `nil` emptiness = not fetched.
    public static func initial(
        preference: NewsDefaultSurface,
        threadedIsEmpty: Bool?,
        boardIsEmpty: Bool?
    ) -> NewsSurface {
        switch preference {
        case .threaded:
            return .threaded
        case .board:
            return .board
        case .automatic:
            return threadedIsEmpty == true && boardIsEmpty == false ? .board : .threaded
        }
    }
}

/// Progress of the first-open news fetch, shown as a Task Manager row.
@Observable
@MainActor
public final class NewsDownload: Identifiable {
    public enum Step: Sendable, Hashable {
        case board
        case threaded
    }

    public enum StepState: Sendable, Hashable {
        case pending
        case running
        case done
    }

    public enum Status: Sendable, Hashable {
        case running
        case completed
        case failed(String)
    }

    nonisolated public let id = UUID()
    public private(set) var steps: [Step] = []
    public private(set) var stepStates: [Step: StepState] = [:]
    public private(set) var status: Status = .running

    /// The fetch task; `cancel()` stops it.
    @ObservationIgnored var task: Task<Void, Never>?

    public init(steps: [Step] = []) {
        for step in steps { add(step) }
    }

    /// Done ÷ total; `nil` (indeterminate) while running with nothing done.
    public var fraction: Double? {
        let doneCount = steps.count { stepStates[$0] == .done }
        if status == .running && doneCount == 0 { return nil }
        guard !steps.isEmpty else { return 1 }
        return Double(doneCount) / Double(steps.count)
    }

    /// E.g. "Board ✓ · Threaded …".
    public var caption: String {
        steps.map { step in
            let name = step == .board
                ? String(localized: "Board", bundle: .module)
                : String(localized: "Threaded", bundle: .module)
            switch stepStates[step] ?? .pending {
            case .pending:
                return name
            case .running:
                return "\(name) …"
            case .done:
                return "\(name) ✓"
            }
        }
        .joined(separator: " · ")
    }

    /// True while `step` is planned but not yet fetched.
    public func isFetching(_ step: Step) -> Bool {
        status == .running && steps.contains(step) && stepStates[step] != .done
    }

    public func cancel() {
        guard status == .running else { return }
        status = .failed(String(localized: "Cancelled", bundle: .module))
        task?.cancel()
    }

    func add(_ step: Step) {
        guard !steps.contains(step) else { return }
        steps.append(step)
        stepStates[step] = .pending
    }

    func begin(_ step: Step) {
        add(step)
        stepStates[step] = .running
    }

    func finish(_ step: Step) {
        stepStates[step] = .done
    }

    func fail(_ message: String) {
        guard status == .running else { return }
        status = .failed(message)
    }

    func complete() {
        guard status == .running else { return }
        status = .completed
    }
}

/// Awaits `operation`, but throws `CancellationError` as soon as the
/// calling task is cancelled. Hotline requests ignore cancellation, so
/// the late reply is simply dropped.
func cancellableFetch<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    let gate = ResumeGate<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
            Task {
                do {
                    gate.resume(with: .success(try await operation()))
                } catch {
                    gate.resume(with: .failure(error))
                }
            }
        }
    } onCancel: {
        gate.resume(with: .failure(CancellationError()))
    }
}

/// Resumes a continuation exactly once, even if the result (e.g. a
/// cancellation) arrives before the continuation is installed.
private final class ResumeGate<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, Error>?
        var early: Result<Value, Error>?
        var resumed = false
    }

    private let state = Mutex(State())

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        let early: Result<Value, Error>? = state.withLock { current in
            guard let early = current.early else {
                current.continuation = continuation
                return nil
            }
            current.early = nil
            return early
        }
        if let early { continuation.resume(with: early) }
    }

    func resume(with result: Result<Value, Error>) {
        let continuation: CheckedContinuation<Value, Error>? = state.withLock { current in
            guard !current.resumed else { return nil }
            current.resumed = true
            guard let continuation = current.continuation else {
                current.early = result
                return nil
            }
            current.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}
