import Foundation
import HeidrunCore
import HeidrunChat
import HeidrunFiles
import HeidrunUI

/// Bridges one host session's events into `NotificationCenterService`
/// posts. Three drivers: `HotlineEvent` cases (PM, chat invite, news,
/// disconnect) via the loop; `notifyConnected()` from the handle's
/// post-agreement `start()`; `notifyTransferFinished` from
/// `FilesViewModel.onTransferFinished`.
@MainActor
final class NotificationCoordinator {
    private let client: any HotlineClient
    private let host: HostIdentity
    private let userListVM: UserListViewModel
    private let service: any NotificationPosting
    private var listenTask: Task<Void, Never>?

    init(
        client: any HotlineClient,
        host: HostIdentity,
        userList: UserListViewModel,
        service: any NotificationPosting = NotificationCenterService.shared
    ) {
        self.client = client
        self.host = host
        self.userListVM = userList
        self.service = service
    }

    func start() async {
        listenTask?.cancel()
        let stream = client.events
        listenTask = Task { [weak self] in
            for await event in stream {
                if Task.isCancelled { break }
                await self?.handle(event)
            }
        }
    }

    func cancel() {
        listenTask?.cancel()
        listenTask = nil
    }

    /// Called from `ConnectionHandle.start()` — no `.connected`
    /// `HotlineEvent` exists (the connect call returning is the signal).
    func notifyConnected() async {
        await service.post(.connected, host: host)
    }

    /// Driven from `markDisconnected` rather than the event stream so
    /// coordinator cancellation can't outrun the broadcast.
    func notifyDisconnected(reason: String?) async {
        await service.post(.disconnected(reason: reason), host: host)
    }

    func notifyTransferFinished(
        filename: String,
        direction: FilesViewModel.TransferDirection
    ) async {
        await service.post(.transferFinished(filename: filename, direction: direction), host: host)
    }

    private func handle(_ event: HotlineEvent) async {
        switch event {
        case let .messageReceived(socket, message):
            let senderName = nickname(forSocket: socket)
            await service.post(.privateMessage(senderName: senderName, body: message), host: host)

        case let .privateChatInvited(_, socket, message):
            let senderName = nickname(forSocket: socket)
            await service.post(.chatInvite(senderName: senderName, message: message), host: host)

        case let .newsPosted(text):
            await service.post(.newsPosted(text: text), host: host)

        case let .broadcastReceived(text):
            await service.post(.broadcast(text: text), host: host)

        case .disconnected, .agreementReceived, .chatReceived,
             .privateChatJoined, .privateChatLeft,
             .privateChatSubjectChanged, .transferQueueUpdated,
             .userChanged, .userLeft, .userListReceived, .userAccessReceived:
            break
        }
    }

    /// Falls back to "user \(socket)" if the roster hasn't seen the
    /// sender yet — better than dropping the notification on a race.
    private func nickname(forSocket socket: UInt16) -> String {
        if let user = userListVM.users.first(where: { $0.socket == socket }),
           !user.nickname.isEmpty {
            return user.nickname
        }
        return "user \(socket)"
    }
}
