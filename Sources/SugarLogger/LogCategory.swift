import Foundation

/// An open-ended tag that groups log entries into categories.
///
/// Built-in categories are provided as static constants.
/// Add your own anywhere in your app:
/// ```swift
/// extension LogCategory {
///     static let payment = LogCategory("payment")
///     static let analytics = LogCategory("analytics")
/// }
/// ```
public struct LogCategory: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    // MARK: - Built-in categories

    /// HTTP requests and responses.
    public static let network  = LogCategory("network")
    /// Thrown errors and exceptions.
    public static let error    = LogCategory("error")
    /// Retry attempts (backoff, reason, attempt number).
    public static let retry    = LogCategory("retry")
    /// Arbitrary app events (user actions, state changes, …).
    public static let event    = LogCategory("event")

    // MARK: - Color

    /// Deterministic color hex derived from the category name.
    /// Standard categories get fixed, recognisable colors; custom ones get a hash-based hue.
    public var colorHex: String {
        switch self {
        case .network: return "#34C759"   // green
        case .error:   return "#FF3B30"   // red
        case .retry:   return "#FF9500"   // orange
        case .event:   return "#AF52DE"   // purple
        default:
            // Derive a deterministic hue from the name hash
            let hue = Double(abs(rawValue.hashValue) % 360) / 360.0
            return hslToHex(hue: hue, saturation: 0.65, lightness: 0.45)
        }
    }

    // MARK: - Private helpers

    private func hslToHex(hue: Double, saturation: Double, lightness: Double) -> String {
        let c = (1 - abs(2 * lightness - 1)) * saturation
        let x = c * (1 - abs(hue * 6 - Double(Int(hue * 6 / 2) * 2) - 1))
        let m = lightness - c / 2
        var r = 0.0, g = 0.0, b = 0.0
        switch Int(hue * 6) {
        case 0: r = c; g = x
        case 1: r = x; g = c
        case 2: g = c; b = x
        case 3: g = x; b = c
        case 4: r = x; b = c
        default: r = c; b = x
        }
        let ri = Int((r + m) * 255), gi = Int((g + m) * 255), bi = Int((b + m) * 255)
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}
