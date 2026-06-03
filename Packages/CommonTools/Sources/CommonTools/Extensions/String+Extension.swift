import Foundation

extension String {
    /// Creates a new string by copying the null-terminated UTF-8 data.
    public init?(cString data: Data) {
        // String(data:encoding:) doesn't handle null-termination
        let value = data.withUnsafeBytes { ptr in
            ptr.bindMemory(to: Int8.self).baseAddress.flatMap(String.init(cString:))
        }

        guard let ret = value else { return nil }
        self = ret
    }
   public static func binaryRepresentation<F: FixedWidthInteger>(of val: F) -> String {

        let binaryString = String(val, radix: 2)

        if val.trailingZeroBitCount > 0 {
            return binaryString + String(repeating: "0", count: val.trailingZeroBitCount)
        }

        return binaryString
    }

    /// strip combining marks (accents or diacritics)
    public var stripCombiningMarks: String {
        let mStringRef = NSMutableString(string: self) as CFMutableString
        CFStringTransform(mStringRef, nil, kCFStringTransformStripCombiningMarks, false)
        return mStringRef as String
    }
}

public extension String.StringInterpolation {
    /// Represents a single numeric radix
    enum Radix: Int {
        case binary = 2, octal = 8, decimal = 10, hex = 16

        /// Returns a radix's optional prefix
        var prefix: String {
            [.binary: "0b", .octal: "0o", .hex: "0x"][self, default: ""]
        }
    }

    /// Return padded version of the value using a specified radix
    mutating func appendInterpolation<I: BinaryInteger>(_ value: I, radix: Radix, prefix: Bool = false, toWidth width: Int = 0, uppercase: Bool = true) {

        // Values are uppercased, producing `FF` instead of `ff`
        var string = String(value, radix: radix.rawValue, uppercase: uppercase)

        // Strings are pre-padded with 0 to match target widths
        if string.count < width {
            string = String(repeating: "0", count: max(0, width - string.count)) + string
        }

        // Prefixes use lower case, sourced from `String.StringInterpolation.Radix`
        if prefix {
            string = radix.prefix + string
        }

        appendInterpolation(string)
    }
    /// Return zero-padded decimal string — lock-free alternative to String(format: "%05d", value)
    mutating func appendInterpolation<I: BinaryInteger>(_ value: I, pad width: Int) {
        var string = String(value)
        if string.count < width {
            string = String(repeating: "0", count: width - string.count) + string
        }
        appendInterpolation(string)
    }

    /// Return fixed-precision decimal string — lock-free alternative to String(format: "%0.3f", value)
    mutating func appendInterpolation(_ value: Double, decimals: Int) {
        let factor = [1.0, 10.0, 100.0, 1000.0, 10000.0, 100000.0, 1000000.0]
        let scaleFactor = decimals < factor.count ? factor[decimals] : pow(10.0, Double(decimals))
        let rounded = Int((value * scaleFactor).rounded())
        let whole = rounded / Int(scaleFactor)
        let frac = abs(rounded) % Int(scaleFactor)
        var fracStr = String(frac)
        if fracStr.count < decimals {
            fracStr = String(repeating: "0", count: decimals - fracStr.count) + fracStr
        }
        appendInterpolation(value < 0 && whole == 0 ? "-\(whole).\(fracStr)" : "\(whole).\(fracStr)")
    }

    /// Return ascii version
    mutating func appendInterpolation<I: BinaryInteger>(_ value: I, toWidth width: Int = 0, fillBlank fill: Bool = true) {
        var scalar = UnicodeScalar(UInt8(value))
        if value < 33 || value > 126 {
            if fill {
                scalar = UnicodeScalar("\u{B7}")
            } else {
                scalar = UnicodeScalar(" ")
            }
        }
        var string = String(scalar)

        if string.count < width {
            string = String(repeating: " ", count: max(0, width - string.count)) + string
        }
        appendInterpolation(string)
    }
}

public extension String {
    var isNumber: Bool {
        let digitsCharacters = CharacterSet(charactersIn: "0123456789,")
        return CharacterSet(charactersIn: self).isSubset(of: digitsCharacters)
    }
}
