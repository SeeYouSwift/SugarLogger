import Foundation

// MARK: - NetworkLogEntry

/// Full HTTP request/response details attached to a network log entry.
public struct NetworkLogEntry: Sendable {

    // MARK: Request

    public let method: String
    public let url: URL?
    public let requestHeaders: [(key: String, value: String)]
    public let requestBody: String?

    // MARK: Response

    public let statusCode: Int?
    public let responseHeaders: [(key: String, value: String)]
    public let responseBody: String?

    // MARK: Timing

    public let durationMs: Int?

    // MARK: Computed

    public var isSuccess: Bool {
        guard let code = statusCode else { return false }
        return (200...299).contains(code)
    }

    public var isError: Bool {
        guard let code = statusCode else { return false }
        return code >= 400
    }

    public var urlPath: String {
        url?.path ?? "/"
    }

    public var host: String {
        url?.host ?? ""
    }

    // MARK: Init — request only (logged before response arrives)

    public init(
        method: String,
        url: URL?,
        requestHeaders: [(key: String, value: String)] = [],
        requestBody: String? = nil
    ) {
        self.method = method
        self.url = url
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.statusCode = nil
        self.responseHeaders = []
        self.responseBody = nil
        self.durationMs = nil
    }

    // MARK: Init — full request + response

    public init(
        method: String,
        url: URL?,
        requestHeaders: [(key: String, value: String)] = [],
        requestBody: String? = nil,
        statusCode: Int,
        responseHeaders: [(key: String, value: String)] = [],
        responseBody: String? = nil,
        durationMs: Int
    ) {
        self.method = method
        self.url = url
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.durationMs = durationMs
    }
}

// MARK: - LogEntry

/// A single log record.
public struct LogEntry: Sendable, Identifiable {

    // MARK: Core

    public let id: UUID
    public let date: Date
    public let level: LogLevel
    public let category: LogCategory
    /// Primary human-readable description of the event.
    public let message: String
    /// Supplementary key-value pairs (URL, status code, duration, body, …).
    public let metadata: [(key: String, value: String)]

    /// Attached network details, if this is a network log entry.
    public let networkEntry: NetworkLogEntry?

    // MARK: Init — generic

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        level: LogLevel,
        category: LogCategory,
        message: String,
        metadata: [(key: String, value: String)] = [],
        networkEntry: NetworkLogEntry? = nil
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata
        self.networkEntry = networkEntry
    }

    /// Convenience init with a dictionary (order not guaranteed).
    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        level: LogLevel,
        category: LogCategory,
        message: String,
        metadataDict: [String: String]
    ) {
        self.init(
            id: id, date: date, level: level, category: category,
            message: message,
            metadata: metadataDict.map { ($0.key, $0.value) }
        )
    }
}
