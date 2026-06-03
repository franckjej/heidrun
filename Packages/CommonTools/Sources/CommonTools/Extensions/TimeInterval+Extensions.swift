import Foundation

public extension TimeInterval {
    func captureString() -> String {
        let totalSeconds = NSInteger(self)
        let milliseconds = Int((self.truncatingRemainder(dividingBy: 1)) * 1000)

        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = (totalSeconds / 3600)
        return " \(hours, pad: 2):\(minutes, pad: 2):\(seconds, pad: 2).\(milliseconds, pad: 3)"
    }
}
