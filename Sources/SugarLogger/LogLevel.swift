import Foundation

/// Severity level of a log entry.
/// Conforms to `Comparable` so you can set a `minimumLevel` threshold.
public enum LogLevel: String, Sendable, CaseIterable, Comparable {
    case debug   = "DEBUG"
    case info    = "INFO"
    case warning = "WARN"
    case error   = "ERROR"

    // MARK: Comparable

    private var order: Int {
        switch self {
        case .debug:   return 0
        case .info:    return 1
        case .warning: return 2
        case .error:   return 3
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.order < rhs.order
    }

    // MARK: Display

    /// Short label padded to 5 characters for aligned output.
    public var paddedLabel: String {
        rawValue.padding(toLength: 5, withPad: " ", startingAt: 0)
    }

    /// SF Symbol name representing this level.
    public var symbolName: String {
        switch self {
        case .debug:   return "circle.fill"
        case .info:    return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.circle.fill"
        }
    }

    /// Color hex string (used by HTML exporter and SwiftUI).
    public var colorHex: String {
        switch self {
        case .debug:   return "#8E8E93"
        case .info:    return "#007AFF"
        case .warning: return "#FF9500"
        case .error:   return "#FF3B30"
        }
    }
}
