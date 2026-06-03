import Foundation
extension Sequence {
    public func unique<T: Hashable>(by keyForValue: (Iterator.Element) throws -> T) rethrows -> [Iterator.Element] {
        var seen: Set<T> = []
        return try filter { try seen.insert(keyForValue($0)).inserted }
    }
}
