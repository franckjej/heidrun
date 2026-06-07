import Foundation
import HeidrunCore
import Observation

/// One line in the protocol console: one Hotline transaction either sent
/// by us or received from a server.
struct ProtocolConsoleEntry: Identifiable, Sendable {
    enum Direction: Sendable {
        case outbound
        case inbound
    }

    enum Kind: Sendable {
        case outboundRequest
        case inboundPush
        /// Reply correlated by taskNumber to a recent outbound request.
        /// Servers frequently stamp these with `transactionID = 0`;
        /// `replyTo` carries the original request's id.
        case inboundReply(replyTo: UInt16)
        /// Inbound transaction we couldn't recognise as a known push and
        /// that didn't correlate to a recent outbound taskNumber — the
        /// dialect-spotting signal.
        case inboundUnknown
    }

    let id: UInt64
    let timestamp: Date
    let server: String
    let direction: Direction
    let kind: Kind
    /// Raw wire transaction id. Rendered as decimal in the UI to match
    /// every Hotline reference doc.
    let transactionID: UInt16
    /// 0 = request/push, 1 = reply. Distinguishes a real reply from a
    /// server push that recycles an outbound task number (HXD/Mobius
    /// behaviour that tripped early reply correlation).
    let classID: UInt16
    let taskNumber: UInt32
    /// `nil` when the id isn't in our known set.
    let knownName: String?
    let fields: [PacketField]

    /// Approximate body size. Lets the row show "X bytes" without re-
    /// encoding the packet.
    var approximateBodySize: Int {
        fields.reduce(0) { $0 + $1.data.count + 8 }
    }

    var isUnknown: Bool {
        if case .inboundUnknown = kind { return true }
        return false
    }
}

/// Main-actor observable store the protocol console binds to. Ring buffer
/// (capacity 2000) so a long session can't run the process out of memory.
@MainActor
@Observable
final class ProtocolConsoleStore {
    static let shared = ProtocolConsoleStore()

    private(set) var entries: [ProtocolConsoleEntry] = []

    /// Lifetime transactions recorded. UI shows it next to the live
    /// count so the user can see how much got trimmed off the head.
    private(set) var totalRecorded: UInt64 = 0

    let capacity: Int = 2000

    private var nextID: UInt64 = 1

    /// Correlation key for an outbound request awaiting its reply. Keyed by
    /// BOTH the connection (`server`) and the task number: each connection
    /// runs its own task counter from 1, so two simultaneous connections
    /// routinely reuse the same task number (e.g. both ping on task 96).
    /// Keying by task number alone let the first reply consume the slot and
    /// rendered the second connection's reply as `???`.
    private struct PendingKey: Hashable {
        let server: String
        let taskNumber: UInt32
    }

    /// `(server, taskNumber) → transactionID` for recent outbound requests.
    /// Used to recognise the matching inbound reply (commonly stamped with
    /// `transactionID = 0`).
    private var pendingTaskNumbers: [PendingKey: UInt16] = [:]

    /// `shared` is the production singleton; `init()` stays accessible so
    /// tests can exercise a fresh, isolated store.
    init() {}

    func append(
        server: String,
        direction: ProtocolConsoleEntry.Direction,
        classID: UInt16,
        transactionID: UInt16,
        taskNumber: UInt32,
        fields: [PacketField]
    ) {
        let kind: ProtocolConsoleEntry.Kind
        let knownName: String?
        switch direction {
        case .outbound:
            kind = .outboundRequest
            knownName = ProtocolConsoleStore.transactionName(for: transactionID)
            pendingTaskNumbers[PendingKey(server: server, taskNumber: taskNumber)] = transactionID

        case .inbound:
            // Only class-1 packets are real replies. A class-0 inbound
            // is always a server push, even if its task number
            // coincidentally matches a pending outbound — some
            // HXD/Mobius servers recycle task numbers on unsolicited
            // pushes (which caused agreement/message rows to be
            // mislabelled as "getUserList reply" in early transcripts).
            let replyKey = PendingKey(server: server, taskNumber: taskNumber)
            if classID == 1, let requestTX = pendingTaskNumbers.removeValue(forKey: replyKey) {
                kind = .inboundReply(replyTo: requestTX)
                knownName = transactionID == 0
                    ? ProtocolConsoleStore.transactionName(for: requestTX)
                    : ProtocolConsoleStore.transactionName(for: transactionID)
            } else if let name = ProtocolConsoleStore.inboundName(for: transactionID) {
                kind = .inboundPush
                knownName = name
            } else {
                kind = .inboundUnknown
                knownName = nil
            }
        }

        let entry = ProtocolConsoleEntry(
            id: nextID,
            timestamp: Date(),
            server: server,
            direction: direction,
            kind: kind,
            transactionID: transactionID,
            classID: classID,
            taskNumber: taskNumber,
            knownName: knownName,
            fields: fields
        )
        nextID &+= 1
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        totalRecorded &+= 1
        // Keep pendingTaskNumbers bounded so the dictionary doesn't grow
        // forever in a long-lived session.
        if pendingTaskNumbers.count > capacity {
            pendingTaskNumbers.removeAll(keepingCapacity: true)
        }
    }

    func clear() {
        entries.removeAll(keepingCapacity: true)
        pendingTaskNumbers.removeAll(keepingCapacity: true)
    }

    static func transactionName(for transactionID: UInt16) -> String? {
        transactionNames[transactionID]
    }

    /// Some IDs mean different things server→client than client→server
    /// (e.g. TX 354 is our outbound `makeUser` admin call, but inbound
    /// it's the HXD/Mobius `userList` push).
    static func inboundName(for transactionID: UInt16) -> String? {
        if let override = inboundNameOverrides[transactionID] { return override }
        return transactionNames[transactionID]
    }

    static let inboundNameOverrides: [UInt16: String] = [
        113: "privateChatInvitation",   // outbound: requestAttention
        117: "privateChatJoined",       // outbound: invite
        118: "privateChatLeft",         // outbound: createPrivateChat
        211: "transferQueueUpdate",     // outbound: downloadFolderReply (we never send this)
        354: "userList"                 // outbound: makeUser (admin); HXD pushes user list / privs here
    ]

    /// Stays in sync with `PacketObserver.knownRequestIDs` and the
    /// `InfoTransaction` enum upstream — add a label here when adding a
    /// new transaction there.
    static let transactionNames: [UInt16: String] = [
        101: "getNewsFile",
        102: "newPost",
        103: "postNewNews",
        104: "message",
        105: "sendChat",
        106: "relayChat",
        107: "login",
        108: "sendPrivateMessage",
        109: "agreement",
        110: "kick",
        111: "disconnected",
        112: "changeChatSubject",
        113: "requestAttention",
        114: "showAgreement",
        115: "joinPrivateChat",
        116: "leavePrivateChat",
        117: "invite",
        118: "createPrivateChat",
        119: "chatSubjectChanged",
        120: "rejectPrivateChat",
        121: "agreeToAgreement",
        200: "listFiles",
        202: "downloadFile",
        203: "uploadFile",
        204: "deleteEntry",
        205: "createFolder",
        206: "getFileInfo",
        207: "setFileInfo",
        208: "moveFile",
        209: "makeAlias",
        210: "downloadFolder",
        211: "downloadFolderReply",
        212: "downloadBanner",
        213: "uploadFolder",
        300: "getUserList",
        301: "userChanged",
        302: "userLeft",
        303: "getUserInfo",
        304: "changeNickname",
        305: "postClientInfo",
        350: "newUser",
        351: "deleteUser",
        352: "openLogin",
        353: "modifyLogin",
        354: "makeUser",
        355: "broadcast",
        370: "getNewsCategoryList",
        371: "getNewsArticleList",
        380: "deleteNewsItem",
        381: "newNewsCategory",
        382: "newNewsItem",
        400: "getNewsArticleData",
        410: "postNewsArticle",
        411: "deleteNewsArticle",
        500: "ping"
    ]
}

extension ProtocolConsoleStore {
    /// Builds a `PacketObserver` that funnels everything from one
    /// connection into this store, tagging entries with `server`.
    func observer(forServer server: String) -> PacketObserver {
        PacketObserver { [weak self] direction, header, fields in
            guard let self else { return }
            let dir: ProtocolConsoleEntry.Direction = (direction == .outbound) ? .outbound : .inbound
            // Capture by value so the @Sendable closure doesn't reach
            // into the actor-isolated PacketHeader at the wrong context.
            let classID = header.classID
            let txID = header.transactionID
            let taskNumber = header.taskNumber
            Task { @MainActor in
                self.append(
                    server: server,
                    direction: dir,
                    classID: classID,
                    transactionID: txID,
                    taskNumber: taskNumber,
                    fields: fields
                )
            }
        }
    }
}
