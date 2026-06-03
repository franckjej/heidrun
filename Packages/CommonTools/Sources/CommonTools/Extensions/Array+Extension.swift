import Cocoa
extension Array {
	mutating func remove(indices: IndexSet) {
		self = self.enumerated().filter { !indices.contains($0.offset) }.map { $0.element }
	}
	public func chunked(into size: Int) -> [[Element]] {
		stride(from: 0, to: count, by: size).map {
			Array(self[$0 ..< Swift.min($0 + size, count)])
		}
	}
    subscript(safe index: Index) -> Element? {
        0 <= index && index < count ? self[index] : nil
    }
    func intersects(range: Range<Int>) -> Bool {
        (self.startIndex..<self.endIndex).overlaps(range)
    }
}
