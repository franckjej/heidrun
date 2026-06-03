import Foundation
import HeidrunCore

/// Composite identity for keychain password I/O. Mirrors the host's
/// `KeychainPasswordStore.Key` without depending on `CommonTools` so
/// the archiver stays a pure transformation.
///
/// Fields are raw — host call sites are responsible for canonicalising
/// `address` (lowercased + trimmed) and `login` (trimmed) before
/// consulting the keychain. The bridge runs `address`/`login` through
/// `CommonTools.KeychainPasswordStore.Key.canonical(...)` at the
/// boundary.
public struct KeychainPasswordKey: Sendable, Hashable {
    public let address: String
    public let port: UInt16
    public let login: String

    public init(address: String, port: UInt16, login: String) {
        self.address = address
        self.port = port
        self.login = login
    }
}

public enum BookmarkArchiveError: Error, LocalizedError, Sendable, Equatable {
    /// The Security framework / Foundation rejected the input data.
    case cannotDecode(String)
    /// The decoded root wasn't an `NSArray`.
    case unexpectedRootType
    /// A dictionary entry was missing a required field.
    case missingField(String)

    public var errorDescription: String? {
        switch self {
        case .cannotDecode(let reason):
            "Couldn't read the bookmarks file (\(reason))."
        case .unexpectedRootType:
            "The bookmarks file has an unexpected layout (root is not a list)."
        case .missingField(let field):
            "The bookmarks file is missing a required field (\(field))."
        }
    }
}

/// Legacy Heidrun `kFavoritesList` round-trip. Produces and consumes
/// `NSKeyedArchiver`-encoded arrays of legacy-shaped dictionaries:
///
/// ```
/// [
///   {
///     "Name": "Carpe Diem", "Address": "hl.example.com",
///     "Port": 5500, "Login": "bob", "Password": "hunter2",
///     "Nick": "Bob", "Icon": 410,
///     "UseDefaultUserInfo": false,
///     "AutoConnectFavorite": false,
///     "AssignFavoriteShortcut": true
///   },
///   ...
/// ]
/// ```
///
/// Password material is injected via closures so this layer never
/// reaches into the keychain itself — keeps the lib testable without
/// real keychain plumbing.
public enum BookmarkArchiver {

    /// Encode `bookmarks` as a legacy-shaped `NSKeyedArchiver` blob.
    /// `readPassword` is called once per bookmark to source the
    /// `Password` field (return empty when nothing's stored).
    public static func archive(
        _ bookmarks: [Bookmark],
        readPassword: (KeychainPasswordKey) -> String?
    ) throws -> Data {
        let array = NSMutableArray()
        for mark in bookmarks {
            let settings = mark.settings
            let key = KeychainPasswordKey(address: settings.address, port: settings.port, login: settings.login)
            let password = readPassword(key) ?? ""
            let dict = NSMutableDictionary(dictionary: [
                "Name": settings.name,
                "Address": settings.address,
                "Port": NSNumber(value: settings.port),
                "Login": settings.login,
                "Password": password,
                "Nick": settings.nickname,
                "Icon": NSNumber(value: settings.icon),
                "UseDefaultUserInfo": NSNumber(value: settings.useDefaultUserInfo),
                "AutoConnectFavorite": NSNumber(value: settings.autoConnectFavorite),
                "AssignFavoriteShortcut": NSNumber(value: settings.assignFavoriteShortcut),
                "UseTLS": NSNumber(value: settings.useTLS)
            ])
            // Only written when present, so cleartext bookmarks stay
            // byte-identical to the pre-pinning archive layout.
            if let pin = settings.pinnedCertificateSHA256 {
                dict["PinnedCertificateSHA256"] = pin
            }
            array.add(dict)
        }
        do {
            return try NSKeyedArchiver.archivedData(withRootObject: array, requiringSecureCoding: true)
        } catch {
            throw BookmarkArchiveError.cannotDecode(error.localizedDescription)
        }
    }

    /// Decode a legacy-shaped blob into `Bookmark`s. Each entry gets a
    /// freshly minted `UUID`. Non-empty `Password` fields are routed
    /// to `writePassword` keyed by `(address, port, login)`.
    public static func unarchive(
        _ data: Data,
        writePassword: (String, KeychainPasswordKey) -> Void
    ) throws -> [Bookmark] {
        // `NSData` is allow-listed because some pre-Unicode legacy
        // versions wrote `Password` as raw bytes (the password field
        // becomes nil after the `as? String` cast below, so it just
        // gets dropped — but the unarchive itself shouldn't fail).
        // Any other unexpected class will fail closed via `cannotDecode`.
        let decoded: Any?
        do {
            decoded = try NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [NSArray.self, NSDictionary.self, NSString.self, NSNumber.self, NSData.self],
                from: data
            )
        } catch {
            throw BookmarkArchiveError.cannotDecode(error.localizedDescription)
        }
        guard let array = decoded as? [NSDictionary] else {
            throw BookmarkArchiveError.unexpectedRootType
        }

        var bookmarks: [Bookmark] = []
        for dict in array {
            let settings = try ConnectionSettings(legacyDictionary: dict)
            bookmarks.append(Bookmark(settings: settings))
            if let password = dict["Password"] as? String, !password.isEmpty {
                let key = KeychainPasswordKey(address: settings.address, port: settings.port, login: settings.login)
                writePassword(password, key)
            }
        }
        return bookmarks
    }
}

// MARK: - ConnectionSettings legacy decoder

private extension ConnectionSettings {
    init(legacyDictionary dict: NSDictionary) throws {
        let name = try Self.requiredString(in: dict, key: "Name")
        let address = try Self.requiredString(in: dict, key: "Address")
        let port = try Self.requiredUInt16(in: dict, key: "Port")
        self.init(
            name: name,
            address: address,
            port: port,
            nickname: (dict["Nick"] as? String) ?? "",
            login: (dict["Login"] as? String) ?? "",
            icon: (dict["Icon"] as? NSNumber).map { UInt16(clamping: $0.intValue) } ?? 0,
            useDefaultUserInfo: (dict["UseDefaultUserInfo"] as? NSNumber)?.boolValue ?? true,
            autoConnectFavorite: (dict["AutoConnectFavorite"] as? NSNumber)?.boolValue ?? false,
            assignFavoriteShortcut: (dict["AssignFavoriteShortcut"] as? NSNumber)?.boolValue ?? false,
            useTLS: (dict["UseTLS"] as? NSNumber)?.boolValue ?? false,
            pinnedCertificateSHA256: dict["PinnedCertificateSHA256"] as? String
        )
    }

    static func requiredString(in dict: NSDictionary, key: String) throws -> String {
        guard let value = dict[key] as? String else {
            throw BookmarkArchiveError.missingField(key)
        }
        return value
    }

    static func requiredUInt16(in dict: NSDictionary, key: String) throws -> UInt16 {
        guard let number = dict[key] as? NSNumber else {
            throw BookmarkArchiveError.missingField(key)
        }
        return UInt16(clamping: number.intValue)
    }
}
