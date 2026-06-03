import Foundation
import Testing
@testable import HeidrunAdmin
import HeidrunCore

@Suite("AdminViewModel")
struct AdminViewModelTests {

    @Test("findAndLoad fetches and populates the form + roster")
    @MainActor
    func findAndLoadPopulates() async {
        let viewModel = AdminViewModel(
            openLogin: { name in
                #expect(name == "tom")
                return ("Tom Sawyer", AdminPrivilegePresets.userPrivileges)
            },
            createLogin: { _, _, _, _ in },
            modifyLogin: { _, _, _, _ in },
            deleteLogin: { _ in }
        )
        viewModel.findQuery = "tom"
        await viewModel.findAndLoad()

        #expect(viewModel.loadedAccount == "tom")
        #expect(viewModel.login == "tom")
        #expect(viewModel.nickname == "Tom Sawyer")
        #expect(viewModel.selection == .existing(login: "tom"))
        #expect(viewModel.preset == .user)
        #expect(viewModel.roster.contains(where: { $0.login == "tom" }))
        #expect(viewModel.changePassword == false)
        #expect(viewModel.password.isEmpty)
        #expect(viewModel.isDirty == false)
    }

    @Test("startNew clears the form and selects .new")
    @MainActor
    func startNewClearsForm() {
        let viewModel = AdminViewModel(
            openLogin: { _ in ("", []) },
            createLogin: { _, _, _, _ in },
            modifyLogin: { _, _, _, _ in },
            deleteLogin: { _ in }
        )
        viewModel.login = "stale"
        viewModel.privileges = [.canBroadcast]
        viewModel.loadedAccount_FOR_TESTING_SET("stale")
        viewModel.startNew()
        #expect(viewModel.selection == .new)
        #expect(viewModel.login.isEmpty)
        #expect(viewModel.privileges.isEmpty)
        #expect(viewModel.loadedAccount == nil)
        #expect(viewModel.changePassword == true)         // implicit-on for .new
    }

    @Test("save creates a new login and upserts the roster")
    @MainActor
    func saveCreatesNewLogin() async {
        let recorder = AdminRecorder()
        let viewModel = AdminViewModel(
            openLogin: { _ in fatalError("no load") },
            createLogin: { name, password, nickname, privs in
                await recorder.recordCreate(name: name, password: password, nickname: nickname, privileges: privs)
            },
            modifyLogin: { _, _, _, _ in
                Issue.record("modify should not be called for a new login")
            },
            deleteLogin: { _ in }
        )
        viewModel.startNew()
        viewModel.login = "carol"
        viewModel.nickname = "Carol"
        viewModel.password = "s3cret"
        viewModel.privileges = AdminPrivilegePresets.userPrivileges
        await viewModel.save()

        let creates = await recorder.creates
        #expect(creates.count == 1)
        #expect(creates.first?.name == "carol")
        #expect(creates.first?.password == "s3cret")
        #expect(viewModel.loadedAccount == "carol")
        #expect(viewModel.roster.contains(where: { $0.login == "carol" }))
        #expect(viewModel.selection == .existing(login: "carol"))
        #expect(viewModel.isDirty == false)
    }

    @Test("save modifies in place when editing a loaded account")
    @MainActor
    func saveModifiesLoadedAccount() async {
        let recorder = AdminRecorder()
        let viewModel = AdminViewModel(
            openLogin: { _ in ("Carol", [.readChat]) },
            createLogin: { _, _, _, _ in
                Issue.record("create should not be called when modifying")
            },
            modifyLogin: { name, password, nickname, privs in
                await recorder.recordModify(name: name, password: password, nickname: nickname, privileges: privs)
            },
            deleteLogin: { _ in }
        )
        viewModel.findQuery = "carol"
        await viewModel.findAndLoad()
        viewModel.setPrivilege(.sendChat, on: true)
        await viewModel.save()

        let modifies = await recorder.modifies
        #expect(modifies.count == 1)
        #expect(modifies.first?.password == nil)
        #expect(modifies.first?.privileges.contains(.sendChat) == true)
        #expect(viewModel.isDirty == false)
    }

    @Test("save with changePassword=true forwards the new password and resets the toggle")
    @MainActor
    func saveSendsPasswordWhenFlipped() async {
        let recorder = AdminRecorder()
        let viewModel = AdminViewModel(
            openLogin: { _ in ("Carol", []) },
            createLogin: { _, _, _, _ in },
            modifyLogin: { name, password, nickname, privs in
                await recorder.recordModify(name: name, password: password, nickname: nickname, privileges: privs)
            },
            deleteLogin: { _ in }
        )
        viewModel.findQuery = "carol"
        await viewModel.findAndLoad()
        viewModel.changePassword = true
        viewModel.password = "newpass"
        await viewModel.save()

        let modifies = await recorder.modifies
        #expect(modifies.first?.password == "newpass")
        #expect(viewModel.password.isEmpty)
        #expect(viewModel.changePassword == false)
    }

    @Test("delete removes from the roster and clears the form")
    @MainActor
    func deleteRemovesRosterEntry() async {
        let recorder = AdminRecorder()
        let viewModel = AdminViewModel(
            openLogin: { _ in ("Carol", []) },
            createLogin: { _, _, _, _ in },
            modifyLogin: { _, _, _, _ in },
            deleteLogin: { name in await recorder.recordDelete(name: name) }
        )
        viewModel.findQuery = "carol"
        await viewModel.findAndLoad()
        await viewModel.delete()

        let deletes = await recorder.deletes
        #expect(deletes == ["carol"])
        #expect(viewModel.loadedAccount == nil)
        #expect(viewModel.login.isEmpty)
        #expect(viewModel.roster.contains(where: { $0.login == "carol" }) == false)
    }

    @Test("selectPreset stamps the bitmask; flipping a bit snaps preset to .custom")
    @MainActor
    func presetStampThenCustom() {
        let viewModel = AdminViewModel(
            openLogin: { _ in ("", []) },
            createLogin: { _, _, _, _ in },
            modifyLogin: { _, _, _, _ in },
            deleteLogin: { _ in }
        )
        viewModel.startNew()
        viewModel.selectPreset(.user)
        #expect(viewModel.preset == .user)
        #expect(viewModel.privileges == AdminPrivilegePresets.userPrivileges)

        viewModel.setPrivilege(.canBroadcast, on: true)
        #expect(viewModel.preset == .custom)
        #expect(viewModel.privileges.contains(.canBroadcast))
    }

    @Test("editing any field marks the view-model dirty until save or revert")
    @MainActor
    func dirtyTracking() async {
        let viewModel = AdminViewModel(
            openLogin: { _ in ("Carol", AdminPrivilegePresets.userPrivileges) },
            createLogin: { _, _, _, _ in },
            modifyLogin: { _, _, _, _ in },
            deleteLogin: { _ in }
        )
        viewModel.findQuery = "carol"
        await viewModel.findAndLoad()
        #expect(viewModel.isDirty == false)
        viewModel.nickname = "Caroline"
        #expect(viewModel.isDirty == true)
        await viewModel.revert()
        #expect(viewModel.isDirty == false)
        #expect(viewModel.nickname == "Carol")
    }

    @Test("setPrivilege toggles single bits")
    @MainActor
    func setPrivilegeToggles() {
        let viewModel = AdminViewModel(
            openLogin: { _ in ("", []) },
            createLogin: { _, _, _, _ in },
            modifyLogin: { _, _, _, _ in },
            deleteLogin: { _ in }
        )
        viewModel.setPrivilege(.uploadFiles, on: true)
        #expect(viewModel.privileges.contains(.uploadFiles))
        viewModel.setPrivilege(.uploadFiles, on: false)
        #expect(!viewModel.privileges.contains(.uploadFiles))
    }

    @Test("startNew + typing into login marks the view-model dirty")
    @MainActor
    func dirtyTrackingForNewDraft() {
        let viewModel = AdminViewModel(
            openLogin: { _ in ("", []) },
            createLogin: { _, _, _, _ in },
            modifyLogin: { _, _, _, _ in },
            deleteLogin: { _ in }
        )
        viewModel.startNew()
        #expect(viewModel.isDirty == false)
        viewModel.login = "carol"
        #expect(viewModel.isDirty == true)
    }

    @Test("selectPreset(.custom) detaches the picker without changing bits")
    @MainActor
    func selectingCustomLeavesBitsAlone() {
        let viewModel = AdminViewModel(
            openLogin: { _ in ("", []) },
            createLogin: { _, _, _, _ in },
            modifyLogin: { _, _, _, _ in },
            deleteLogin: { _ in }
        )
        viewModel.startNew()
        viewModel.selectPreset(.admin)
        #expect(viewModel.preset == .admin)
        let snapshotBits = viewModel.privileges
        viewModel.selectPreset(.custom)
        #expect(viewModel.preset == .custom)
        #expect(viewModel.privileges == snapshotBits)
    }
}

@Suite("AdminFeature")
struct AdminFeatureTests {
    @Test("static metadata is stable")
    func metadata() {
        #expect(AdminFeature.identifier == "com.heidrun.admin")
        #expect(AdminFeature.displayName == "Admin")
        #expect(!AdminFeature.systemImage.isEmpty)
    }
}

private actor AdminRecorder {
    struct Create: Sendable {
        let name: String
        let password: String
        let nickname: String
        let privileges: UserPrivileges
    }
    struct Modify: Sendable {
        let name: String
        let password: String?
        let nickname: String
        let privileges: UserPrivileges
    }

    private(set) var creates: [Create] = []
    private(set) var modifies: [Modify] = []
    private(set) var deletes: [String] = []

    func recordCreate(name: String, password: String, nickname: String, privileges: UserPrivileges) {
        creates.append(Create(name: name, password: password, nickname: nickname, privileges: privileges))
    }

    func recordModify(name: String, password: String?, nickname: String, privileges: UserPrivileges) {
        modifies.append(Modify(name: name, password: password, nickname: nickname, privileges: privileges))
    }

    func recordDelete(name: String) {
        deletes.append(name)
    }
}

@Suite("AdminPrivilegePresets")
struct AdminPrivilegePresetsTests {
    @Test("guest preset is read-only basics")
    func guestPreset() {
        let guest = AdminPrivilegePresets.guestPrivileges
        #expect(guest.contains(.downloadFiles))
        #expect(guest.contains(.readChat))
        #expect(guest.contains(.readNews))
        #expect(!guest.contains(.uploadFiles))
        #expect(!guest.contains(.canBroadcast))
    }

    @Test("user preset extends guest with participation rights")
    func userPreset() {
        let user = AdminPrivilegePresets.userPrivileges
        #expect(user.contains(.uploadFiles))
        #expect(user.contains(.sendChat))
        #expect(user.contains(.postNews))
        #expect(user.contains(.sendMessages))
        #expect(!user.contains(.canBroadcast))
    }

    @Test("moderator preset adds disciplinary powers")
    func moderatorPreset() {
        let moderator = AdminPrivilegePresets.moderatorPrivileges
        #expect(moderator.contains(.disconnectUsers))
        #expect(moderator.contains(.deleteArticles))
        #expect(moderator.contains(.getUserInfo))
        #expect(!moderator.contains(.createUser))
    }

    @Test("admin preset is the union of all defined bits")
    func adminPreset() {
        let admin = AdminPrivilegePresets.adminPrivileges
        #expect(admin.contains(.createUser))
        #expect(admin.contains(.canBroadcast))
        #expect(admin.contains(.deleteUser))
        #expect(admin.contains(.makeAliases))
    }

    @Test("detect returns the matching preset; .custom otherwise")
    func detectMatching() {
        #expect(AdminPrivilegePresets.detect(AdminPrivilegePresets.guestPrivileges) == .guest)
        #expect(AdminPrivilegePresets.detect(AdminPrivilegePresets.userPrivileges) == .user)
        #expect(AdminPrivilegePresets.detect(AdminPrivilegePresets.moderatorPrivileges) == .moderator)
        #expect(AdminPrivilegePresets.detect(AdminPrivilegePresets.adminPrivileges) == .admin)

        var mixed = AdminPrivilegePresets.userPrivileges
        mixed.insert(.canBroadcast)
        #expect(AdminPrivilegePresets.detect(mixed) == .custom)
    }
}
