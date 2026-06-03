import Foundation

public extension NotificationCenter {
    static let operations: NotificationCenter = {
        let center = NotificationCenter()
        return center
    }()

    static let document: NotificationCenter = {
        let center = NotificationCenter()
        return center
    }()
}
