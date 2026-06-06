import Foundation
import Observation
import HeidrunCore

/// View-model for the admin pane. Owns a session roster (accounts the
/// operator has touched in this connection), the form fields for one
/// editor draft, dirty tracking, and routing of save/delete/revert
/// through the four Hotline account-administration transactions.
@Observable
@MainActor
public final class AdminViewModel {

    public enum Selection: Hashable, Sendable {
        case new
        case existing(login: String)
    }

    public struct RosterEntry: Identifiable, Hashable, Sendable {
        public let login: String
        public var nickname: String
        public var preset: AdminPrivilegePresets.Name
        public var isDirty: Bool
        public var id: String { login }
    }

    // MARK: Sidebar state

    public private(set) var roster: [RosterEntry] = []
    public var selection: Selection?
    public var findQuery: String = ""

    // MARK: Form state

    public var login: String = "" {
        didSet { markDirtyIfFormChanged() }
    }
    public var nickname: String = "" {
        didSet { markDirtyIfFormChanged() }
    }
    public var password: String = "" {
        didSet { markDirtyIfFormChanged() }
    }
    public var changePassword: Bool = false {
        didSet { markDirtyIfFormChanged() }
    }
    public var privileges: UserPrivileges = [] {
        didSet { markDirtyIfFormChanged() }
    }
    public var preset: AdminPrivilegePresets.Name = .custom

    public private(set) var loadedAccount: String?
    public private(set) var isDirty: Bool = false
    public private(set) var isWorking: Bool = false

    /// Transient, semantic status from the last successful intent.
    /// Surfaces in the detail footer so the operator sees a confirmation
    /// after Save / Delete / Revert / Load. Auto-clears after a few
    /// seconds via `noticeAutoClearTask`.
    public enum Notice: Equatable, Sendable {
        case loaded(login: String)
        case created(login: String)
        case saved(login: String)
        case deleted(login: String)
        case reverted(login: String)

        public var login: String {
            switch self {
            case .loaded(let login),
                 .created(let login),
                 .saved(let login),
                 .deleted(let login),
                 .reverted(let login):
                return login
            }
        }

        /// Operator-facing sentence for the status label.
        public var message: String {
            switch self {
            case .loaded(let login):
                return "Loaded \(login)"
            case .created(let login):
                return "Created \(login)"
            case .saved(let login):
                return "Saved \(login)"
            case .deleted(let login):
                return "Deleted \(login)"
            case .reverted(let login):
                return "Reverted \(login)"
            }
        }
    }

    public private(set) var lastNotice: Notice?
    private var noticeAutoClearTask: Task<Void, Never>?

    /// How long a status notice stays visible before auto-clearing.
    private static let noticeVisibleDuration: Duration = .seconds(3)

    // MARK: Injection

    private let openLoginAt: @Sendable (String) async throws -> (String, UserPrivileges)
    private let createLoginAt: @Sendable (String, String, String, UserPrivileges) async throws -> Void
    private let modifyLoginAt: @Sendable (String, String?, String, UserPrivileges) async throws -> Void
    private let deleteLoginAt: @Sendable (String) async throws -> Void
    private let present: @MainActor (Error) -> Void

    /// Tracks the values that were last loaded from the server so dirty
    /// detection compares against ground truth and `revert()` can restore.
    private struct LoadedSnapshot {
        var login: String
        var nickname: String
        var privileges: UserPrivileges
    }
    private var loadedSnapshot: LoadedSnapshot?
    private var isApplyingSnapshot = false

    public init(
        openLogin: @escaping @Sendable (String) async throws -> (String, UserPrivileges),
        createLogin: @escaping @Sendable (String, String, String, UserPrivileges) async throws -> Void,
        modifyLogin: @escaping @Sendable (String, String?, String, UserPrivileges) async throws -> Void,
        deleteLogin: @escaping @Sendable (String) async throws -> Void,
        present: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        self.openLoginAt = openLogin
        self.createLoginAt = createLogin
        self.modifyLoginAt = modifyLogin
        self.deleteLoginAt = deleteLogin
        self.present = present
    }

    public convenience init(
        client: any HotlineClient,
        present: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        self.init(
            openLogin: { [client] name in try await client.openLogin(name) },
            createLogin: { [client] name, password, nickname, privs in
                try await client.createLogin(name: name, password: password, nickname: nickname, privileges: privs)
            },
            modifyLogin: { [client] name, password, nickname, privs in
                try await client.modifyLogin(name: name, password: password, nickname: nickname, privileges: privs)
            },
            deleteLogin: { [client] name in try await client.deleteLogin(name) },
            present: present
        )
    }

    // MARK: Intents

    public func findAndLoad() async {
        let target = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        await loadInto(login: target)
    }

    public func selectExisting(login: String) async {
        guard login != loadedAccount else { return }
        await loadInto(login: login)
    }

    public func startNew() {
        applySnapshot(.init(login: "", nickname: "", privileges: []))
        loadedAccount = nil
        loadedSnapshot = nil
        selection = .new
        changePassword = true
        password = ""
        preset = .custom
        isDirty = false
        noticeAutoClearTask?.cancel()
        lastNotice = nil
    }

    public func duplicate(login sourceLogin: String) async {
        guard let entry = roster.first(where: { $0.login == sourceLogin }) else { return }
        // Load the source so the privilege bits are fresh, then clear
        // the login to force the operator to pick a new name.
        await loadInto(login: sourceLogin)
        loadedAccount = nil           // moved up so dirty bookkeeping for sourceLogin stops first
        loadedSnapshot = nil
        login = ""
        selection = .new
        changePassword = true
        password = ""
        preset = entry.preset
        isDirty = true
    }

    public func save() async {
        let target = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        let nicknameCopy = nickname
        let passwordCopy = password
        let shouldSendPassword = changePassword
        let privsCopy = privileges

        if let loaded = loadedAccount, loaded == target {
            await runWorking {
                try await self.modifyLoginAt(
                    target,
                    shouldSendPassword ? passwordCopy : nil,
                    nicknameCopy,
                    privsCopy
                )
                self.setNotice(.saved(login: target))
                self.changePassword = false
                self.password = ""
                self.loadedSnapshot = .init(login: target, nickname: nicknameCopy, privileges: privsCopy)
                self.isDirty = false
                self.upsertRoster(login: target, nickname: nicknameCopy, privileges: privsCopy, isDirty: false)
            }
        } else {
            await runWorking {
                try await self.createLoginAt(target, passwordCopy, nicknameCopy, privsCopy)
                self.loadedAccount = target
                self.selection = .existing(login: target)
                self.setNotice(.created(login: target))
                self.changePassword = false
                self.password = ""
                self.loadedSnapshot = .init(login: target, nickname: nicknameCopy, privileges: privsCopy)
                self.isDirty = false
                self.upsertRoster(login: target, nickname: nicknameCopy, privileges: privsCopy, isDirty: false)
            }
        }
    }

    public func delete() async {
        guard let loaded = loadedAccount else { return }
        await deleteRow(login: loaded)
    }

    public func deleteRow(login target: String) async {
        await runWorking {
            try await self.deleteLoginAt(target)
            self.roster.removeAll { $0.login == target }
            self.setNotice(.deleted(login: target))
            if self.loadedAccount == target {
                self.resetFormState()
            }
        }
    }

    public func revert() async {
        guard let loaded = loadedAccount else { return }
        await loadInto(login: loaded, asRevert: true)
    }

    public func selectPreset(_ next: AdminPrivilegePresets.Name) {
        if next == .custom {
            // Operator explicitly chose Custom — keep the current bits but
            // detach the picker label from any named preset.
            preset = .custom
            return
        }
        let bits = AdminPrivilegePresets.privileges(for: next)
        isApplyingSnapshot = true
        privileges = bits
        isApplyingSnapshot = false
        preset = next
        recomputeDirty()
    }

    public func setPrivilege(_ privilege: UserPrivileges, on: Bool) {
        var updated = privileges
        if on { updated.insert(privilege) } else { updated.remove(privilege) }
        privileges = updated
        preset = AdminPrivilegePresets.detect(updated)
    }

    public func binding(for privilege: UserPrivileges) -> Bool {
        privileges.contains(privilege)
    }

    // MARK: Internals

    private func loadInto(login target: String, asRevert: Bool = false) async {
        await runWorking {
            let (nicknameValue, privilegesValue) = try await self.openLoginAt(target)
            self.applySnapshot(.init(login: target, nickname: nicknameValue, privileges: privilegesValue))
            self.loadedAccount = target
            self.loadedSnapshot = .init(login: target, nickname: nicknameValue, privileges: privilegesValue)
            self.password = ""
            self.changePassword = false
            self.selection = .existing(login: target)
            self.preset = AdminPrivilegePresets.detect(privilegesValue)
            self.isDirty = false
            self.setNotice(asRevert ? .reverted(login: target) : .loaded(login: target))
            self.upsertRoster(login: target, nickname: nicknameValue, privileges: privilegesValue, isDirty: false)
        }
    }

    private func applySnapshot(_ snapshot: LoadedSnapshot) {
        isApplyingSnapshot = true
        login = snapshot.login
        nickname = snapshot.nickname
        privileges = snapshot.privileges
        isApplyingSnapshot = false
    }

    private func resetFormState() {
        applySnapshot(.init(login: "", nickname: "", privileges: []))
        loadedAccount = nil
        loadedSnapshot = nil
        selection = nil
        changePassword = false
        password = ""
        preset = .custom
        isDirty = false
    }

    private func upsertRoster(
        login target: String,
        nickname displayed: String,
        privileges privs: UserPrivileges,
        isDirty rowDirty: Bool
    ) {
        let presetName = AdminPrivilegePresets.detect(privs)
        let entry = RosterEntry(login: target, nickname: displayed, preset: presetName, isDirty: rowDirty)
        if let existingIndex = roster.firstIndex(where: { $0.login == target }) {
            roster[existingIndex] = entry
        } else {
            roster.append(entry)
            roster.sort { $0.login < $1.login }
        }
    }

    private func markDirtyIfFormChanged() {
        guard !isApplyingSnapshot else { return }
        recomputeDirty()
        if let loaded = loadedAccount {
            if let existingIndex = roster.firstIndex(where: { $0.login == loaded }) {
                roster[existingIndex].isDirty = isDirty
            }
        }
    }

    private func recomputeDirty() {
        if let snapshot = loadedSnapshot {
            isDirty =
                login != snapshot.login
                || nickname != snapshot.nickname
                || privileges != snapshot.privileges
                || changePassword
        } else {
            // .new flow: dirty as soon as anything is filled in.
            isDirty = !login.isEmpty || !nickname.isEmpty || !privileges.isEmpty || changePassword
        }
    }

    private func runWorking(_ work: @MainActor () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            present(error)
        }
    }

    /// Publish a status notice and schedule it to clear automatically.
    private func setNotice(_ notice: Notice) {
        lastNotice = notice
        noticeAutoClearTask?.cancel()
        noticeAutoClearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.noticeVisibleDuration)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                if self.lastNotice == notice {
                    self.lastNotice = nil
                }
            }
        }
    }

    // MARK: Test-only seam

    /// Test-only helper so `AdminViewModelTests.startNewClearsForm` can
    /// pre-set `loadedAccount` without dragging in the closure plumbing.
    /// Intentionally `internal` so `@testable import` exposes it to tests
    /// without requiring an `@_spi` import that confuses SwiftLint.
    func loadedAccount_FOR_TESTING_SET(_ value: String?) {
        loadedAccount = value
    }
}
