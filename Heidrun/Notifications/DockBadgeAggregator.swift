import AppKit
import Observation

/// Single writer for Dock attention: badge = unread total across every
/// connection, bounce on any new pulse while Heidrun is in the background.
/// Re-registers Observation tracking after each change.
@MainActor
final class DockBadgeAggregator {
    static let shared = DockBadgeAggregator()

    private let attentionStates: @MainActor () -> [AttentionState]
    private let defaults: UserDefaults
    private let setBadge: @MainActor (String) -> Void
    private let bounce: @MainActor () -> Void
    private let isAppActive: @MainActor () -> Bool
    private var lastPulseSum = 0
    private var started = false

    init(
        attentionStates: @escaping @MainActor () -> [AttentionState] = {
            ActiveConnections.shared.connections.map(\.attention)
        },
        defaults: UserDefaults = .standard,
        setBadge: @escaping @MainActor (String) -> Void = { NSApp?.dockTile.badgeLabel = $0 },
        bounce: @escaping @MainActor () -> Void = { NSApp?.requestUserAttention(.criticalRequest) },
        isAppActive: @escaping @MainActor () -> Bool = { NSApp?.isActive ?? true }
    ) {
        self.attentionStates = attentionStates
        self.defaults = defaults
        self.setBadge = setBadge
        self.bounce = bounce
        self.isAppActive = isAppActive
    }

    func start() {
        guard !started else { return }
        started = true
        observe()
    }

    private func observe() {
        withObservationTracking {
            refresh()
        } onChange: {
            Task { @MainActor [weak self] in self?.observe() }
        }
    }

    /// Recompute and push. Internal so tests can drive it directly.
    func refresh() {
        let states = attentionStates()
        let total = states.reduce(0) { $0 + $1.total }
        let badgeEnabled = defaults.object(forKey: AppStorageKeys.dockBadgeForUnreadMessages) as? Bool ?? true
        setBadge(badgeEnabled && total > 0 ? String(total) : "")

        let pulseSum = states.reduce(0) { $0 + $1.pulseToken }
        guard pulseSum != lastPulseSum else { return }
        lastPulseSum = pulseSum
        let bounceEnabled = defaults.object(forKey: AppStorageKeys.dockBounceOnPrivateMessage) as? Bool ?? true
        if bounceEnabled, !isAppActive() {
            bounce()
        }
    }
}
