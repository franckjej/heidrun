import Combine
import Foundation

public final class AsyncTimer: Sendable {
    public static func createTimerStream(interval: TimeInterval, limit: Int? = nil) -> AsyncStream<Date> {
        nonisolated(unsafe) var counter = 0
        return AsyncStream { continuation in
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
                let now = Date()
                debugPrint(now)
                continuation.yield(now) // Send the current date to the stream
                counter += 1
                if let limit = limit, counter >= limit {
                    timer.invalidate() // Stop the timer
                    continuation.finish() // Signal the stream is complete
                }
            }

            continuation.onTermination = { _ in
                timer.invalidate() // Ensure the timer is stopped if the stream is canceled
            }
        }
    }

    // Example Usage:
    func runTimerExample() async {
        let timerStream = AsyncTimer.createTimerStream(interval: 1.0, limit: 5) // Fires every second, 5 times
        for await _ in timerStream {
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
        }
    }
}

extension Timer: @retroactive @unchecked Sendable {}
/// Call the example function
/// Task {
///    await runTimerExample()
/// }
