import HeidrunCore

/// Named privilege bundles the operator can stamp onto an account.
///
/// The set of bits each preset toggles is fixed — flipping any single
/// privilege in the UI after a preset has been selected snaps the picker
/// back to `.custom` so the operator can tell their edits diverged from
/// the preset.
public enum AdminPrivilegePresets {

    public enum Name: String, CaseIterable, Hashable, Sendable {
        case guest, user, moderator, admin, custom
    }

    public static let guestPrivileges: UserPrivileges = [
        .downloadFiles, .readChat, .readNews, .useAnyName, .showInList
    ]

    public static let userPrivileges: UserPrivileges = [
        .downloadFiles, .uploadFiles, .readChat, .sendChat,
        .readNews, .postNews, .useAnyName, .showInList,
        .sendMessages, .initiatePrivateChat, .closePrivateChat,
        .getUserInfo, .changeOwnPassword, .makeAliases,
        .commentFiles, .commentFolders, .downloadFolders, .uploadFolders
    ]

    public static let moderatorPrivileges: UserPrivileges = {
        var bits = userPrivileges
        bits.formUnion([
            .disconnectUsers, .deleteArticles, .deleteFiles, .deleteFolders,
            .renameFiles, .renameFolders, .moveFiles, .moveFolders,
            .viewDropBoxes
        ])
        return bits
    }()

    public static let adminPrivileges: UserPrivileges = [
        .deleteFiles, .uploadFiles, .downloadFiles, .renameFiles, .moveFiles,
        .createFolders, .deleteFolders, .renameFolders, .moveFolders,
        .readChat, .sendChat, .initiatePrivateChat, .closePrivateChat,
        .showInList, .createUser, .deleteUser, .readUser, .modifyUser,
        .changeOwnPassword, .readNews, .postNews, .disconnectUsers,
        .cannotBeDisconnected, .getUserInfo, .uploadAnywhere, .useAnyName,
        .dontShowAgreement, .commentFiles, .commentFolders, .viewDropBoxes,
        .makeAliases, .canBroadcast, .deleteArticles, .createCategories,
        .deleteCategories, .createNewsBundles, .deleteNewsBundles,
        .uploadFolders, .downloadFolders, .sendMessages
    ]

    public static func privileges(for preset: Name) -> UserPrivileges {
        switch preset {
        case .guest:
            return guestPrivileges
        case .user:
            return userPrivileges
        case .moderator:
            return moderatorPrivileges
        case .admin:
            return adminPrivileges
        case .custom:
            return []
        }
    }

    public static func detect(_ privileges: UserPrivileges) -> Name {
        if privileges == guestPrivileges { return .guest }
        if privileges == userPrivileges { return .user }
        if privileges == moderatorPrivileges { return .moderator }
        if privileges == adminPrivileges { return .admin }
        return .custom
    }
}
