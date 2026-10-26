import Foundation

/// First News open on a threaded server: fetches board and/or threaded
/// news per the user's settings, tracks it as a `NewsDownload`, then
/// picks the surface. Runs once per connection.
@MainActor
enum NewsInitialLoad {
    static func start(
        plain: PlainNewsViewModel,
        threaded: ThreadedNewsViewModel,
        preference: NewsDefaultSurface,
        downloadsBoth: Bool
    ) {
        guard !threaded.didStartInitialLoad else { return }
        threaded.didStartInitialLoad = true

        // A manual pick shows at once, so its spinner is the right one.
        switch preference {
        case .threaded:
            threaded.surface = .threaded
        case .board:
            threaded.surface = .board
        case .automatic:
            break
        }

        let steps: [NewsDownload.Step] = if downloadsBoth {
            [.threaded, .board]
        } else {
            preference == .board ? [.board] : [.threaded]
        }
        let download = NewsDownload(steps: steps)
        threaded.download = download
        download.task = Task {
            await run(
                download: download,
                plain: plain,
                threaded: threaded,
                preference: preference,
                downloadsBoth: downloadsBoth
            )
        }
    }

    private static func run(
        download: NewsDownload,
        plain: PlainNewsViewModel,
        threaded: ThreadedNewsViewModel,
        preference: NewsDefaultSurface,
        downloadsBoth: Bool
    ) async {
        let surfaceAtStart = threaded.surface
        var threadedIsEmpty: Bool?
        var boardIsEmpty: Bool?

        if downloadsBoth {
            async let threadedResult = runStep(.threaded, in: download) {
                try await threaded.loadBundlesForDownload()
            }
            async let boardResult = runStep(.board, in: download) {
                try await plain.loadForDownload()
            }
            threadedIsEmpty = await threadedResult
            boardIsEmpty = await boardResult
        } else if preference == .board {
            boardIsEmpty = await runStep(.board, in: download) {
                try await plain.loadForDownload()
            }
        } else {
            threadedIsEmpty = await runStep(.threaded, in: download) {
                try await threaded.loadBundlesForDownload()
            }
            if preference == .automatic, threadedIsEmpty == true, !Task.isCancelled {
                boardIsEmpty = await runStep(.board, in: download) {
                    try await plain.loadForDownload()
                }
            }
        }

        download.complete()
        // Leave a surface the user picked mid-load alone.
        guard threaded.surface == surfaceAtStart else { return }
        threaded.surface = NewsSurface.initial(
            preference: preference,
            threadedIsEmpty: threadedIsEmpty,
            boardIsEmpty: boardIsEmpty
        )
    }

    /// Runs one fetch; `nil` when it failed or was cancelled.
    private static func runStep(
        _ step: NewsDownload.Step,
        in download: NewsDownload,
        _ load: @MainActor () async throws -> Bool
    ) async -> Bool? {
        download.begin(step)
        do {
            let isEmpty = try await load()
            download.finish(step)
            return isEmpty
        } catch is CancellationError {
            return nil
        } catch {
            download.fail(error.localizedDescription)
            return nil
        }
    }
}
