import Foundation

// MARK: - LogStreamEvent

/// Events emitted by `SugarLogger.stream`.
public enum LogStreamEvent: Sendable {
    /// A brand-new entry was added to the log.
    case added(LogEntry)
    /// An existing entry (same `entry.id`) was replaced in-place.
    /// Subscribers should find the old row by `entry.id` and swap it.
    case replaced(LogEntry)
}

// MARK: - Export format

/// Supported export file formats.
public enum LogExportFormat: String, CaseIterable, Sendable {
    case txt  = "TXT"
    case json = "JSON"
    case csv  = "CSV"
    case html = "HTML"

    /// File extension for the export.
    public var fileExtension: String {
        switch self {
        case .txt:  return "txt"
        case .json: return "json"
        case .csv:  return "csv"
        case .html: return "html"
        }
    }

    /// Human-readable description shown in the export sheet.
    public var description: String {
        switch self {
        case .txt:  return "Plain Text — readable, one block per event"
        case .json: return "JSON — machine-readable, ideal for log tools"
        case .csv:  return "CSV — spreadsheet-friendly table"
        case .html: return "HTML — styled table, opens in browser"
        }
    }
}

// MARK: - LogViewerState

/// Observable bridge between the actor and SwiftUI.
/// `@unchecked Sendable` is safe: `isPresented` is only mutated on the main actor via `presentViewer()`.
public final class LogViewerState: ObservableObject, @unchecked Sendable {
    @MainActor @Published public var isPresented: Bool = false
    public init() {}
}

// MARK: - SugarLogger

/// Thread-safe logger backed by a Swift actor.
///
/// Use `SugarLogger.shared` anywhere or create a custom instance.
///
/// ```swift
/// // Fire-and-forget — no Task, no await needed:
/// SugarLogger.shared.log("User tapped checkout", category: .event)
///
/// // Show the log viewer from anywhere (synchronous):
/// SugarLogger.shared.presentViewer()
/// ```
public actor SugarLogger {

    // MARK: Singleton

    public static let shared = SugarLogger()

    // MARK: Configuration

    /// Entries below this level are silently dropped.
    public var minimumLevel: LogLevel = .debug

    /// If non-nil, only these categories are recorded.
    public var enabledCategories: Set<LogCategory>? = nil

    /// When `true`, network interceptors include request/response bodies and headers.
    public var verbose: Bool = false

    /// Maximum number of entries kept in memory (ring buffer).
    public var maxEntries: Int = 2000

    // MARK: Storage

    private var entries: [LogEntry] = []
    private let sessionDate = Date()

    // MARK: Live stream

    private var continuation: AsyncStream<LogStreamEvent>.Continuation?

    /// Subscribe to this stream to receive live log events.
    /// Each value is either `.added(entry)` for new entries or
    /// `.replaced(entry)` when a pending entry is updated in-place.
    public let stream: AsyncStream<LogStreamEvent>

    // MARK: Viewer presentation flag (MainActor-isolated observable)

    /// Set to `true` to trigger the log viewer sheet.
    /// Observed by the `logViewer()` SwiftUI modifier.
    nonisolated public let viewerState: LogViewerState

    // MARK: Init

    /// Create a logger with an externally-provided `LogViewerState`.
    /// Use this when you need a custom instance.
    public init(maxEntries: Int = 2000, viewerState: LogViewerState) {
        self.maxEntries = maxEntries
        self.viewerState = viewerState
        var cont: AsyncStream<LogStreamEvent>.Continuation?
        // .bufferingNewest(0) — drop events when there is no active consumer
        // (i.e. the log viewer is closed). The viewer always bootstraps from
        // allEntries() on open, so missed events are never a problem.
        self.stream = AsyncStream(bufferingPolicy: .bufferingNewest(0)) { cont = $0 }
        self.continuation = cont
    }

    /// Convenience init used by `SugarLogger.shared`.
    /// Creates its own `LogViewerState` on the main actor synchronously.
    public init(maxEntries: Int = 2000) {
        self.maxEntries = maxEntries
        self.viewerState = LogViewerState()
        var cont: AsyncStream<LogStreamEvent>.Continuation?
        self.stream = AsyncStream(bufferingPolicy: .bufferingNewest(0)) { cont = $0 }
        self.continuation = cont
    }

    // MARK: - Logging

    /// Fire-and-forget log — call from any synchronous context, no `await` needed.
    ///
    /// ```swift
    /// SugarLogger.shared.log("User tapped Pay", category: .event)
    /// SugarLogger.shared.log("Token missing", level: .error, category: .error)
    /// ```
    nonisolated public func log(
        _ message: String,
        level: LogLevel = .info,
        category: LogCategory = .event,
        metadata: [(key: String, value: String)] = []
    ) {
        let logger = self
        Task { await logger.logIsolated(message, level: level, category: category, metadata: metadata) }
    }

    /// Fire-and-forget log with a metadata dictionary — no `await` needed.
    nonisolated public func log(
        _ message: String,
        level: LogLevel = .info,
        category: LogCategory = .event,
        metadataDict: [String: String]
    ) {
        log(message, level: level, category: category,
            metadata: metadataDict.map { ($0.key, $0.value) })
    }

    // MARK: - Network logging

    /// Log a completed HTTP request. Fire-and-forget — no `await` needed.
    ///
    /// Use this when you have a custom HTTP client and want rich network entries
    /// in the log viewer (REQUEST / RESPONSE sections with headers and body).
    ///
    /// ```swift
    /// // Success
    /// SugarLogger.shared.logNetwork(
    ///     method: "GET", url: url,
    ///     statusCode: 200, durationMs: 320,
    ///     responseBody: jsonString
    /// )
    ///
    /// // Failure
    /// SugarLogger.shared.logNetwork(
    ///     method: "POST", url: url,
    ///     error: networkError
    /// )
    /// ```
    nonisolated public func logNetwork(
        method: String,
        url: URL?,
        requestHeaders: [(key: String, value: String)] = [],
        requestBody: String? = nil,
        statusCode: Int? = nil,
        responseHeaders: [(key: String, value: String)] = [],
        responseBody: String? = nil,
        durationMs: Int? = nil,
        error: Error? = nil
    ) {
        let logger = self
        Task {
            await logger.logNetworkIsolated(
                method: method, url: url,
                requestHeaders: requestHeaders, requestBody: requestBody,
                statusCode: statusCode,
                responseHeaders: responseHeaders, responseBody: responseBody,
                durationMs: durationMs,
                error: error
            )
        }
    }

    // MARK: - Store (for adapters in other modules)

    /// Store a pre-built `LogEntry` directly.
    ///
    /// Use this from adapter types that live outside `SugarLogger` (e.g. `NetworkLoggerAdapter`)
    /// to inject a fully-formed entry without re-creating it from scratch.
    public func store(_ entry: LogEntry) {
        guard entry.level >= minimumLevel else { return }
        if let allowed = enabledCategories, !allowed.contains(entry.category) { return }
        enqueue(entry)
    }

    // MARK: - Network event logging (used by NetworkLoggerAdapter)

    /// Handle a network log entry from `NetworkLoggerAdapter`.
    ///
    /// For network entries `LogEntry.id == NetworkEvent.requestID`, so both the
    /// pending "⏳" entry and the final "← 200" entry share the same id.
    /// - If an entry with the same id already exists → emits `.replaced` (in-place swap).
    /// - Otherwise → emits `.added` as a new row.
    ///
    /// Everything runs in one actor hop: no separate Tasks, no ordering surprises.
    public func storeNetworkEvent(_ entry: LogEntry) {
        guard entry.level >= minimumLevel else { return }
        if let allowed = enabledCategories, !allowed.contains(entry.category) { return }

        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            // Same id → this is a completion for an existing pending entry.
            entries[idx] = entry
            continuation?.yield(.replaced(entry))
        } else {
            enqueue(entry)
        }
    }

    // MARK: - Query

    /// All entries, optionally filtered.
    public func allEntries(
        level: LogLevel? = nil,
        category: LogCategory? = nil
    ) -> [LogEntry] {
        entries.filter { e in
            (level == nil || e.level >= level!) &&
            (category == nil || e.category == category!)
        }
    }

    /// All entries matching a search string (case-insensitive, message + metadata).
    public func allEntries(matching search: String) -> [LogEntry] {
        guard !search.isEmpty else { return entries }
        let q = search.lowercased()
        return entries.filter { e in
            e.message.lowercased().contains(q) ||
            e.metadata.contains { $0.key.lowercased().contains(q) || $0.value.lowercased().contains(q) }
        }
    }

    /// Total number of stored entries.
    public var count: Int { entries.count }

    // MARK: - Clear

    /// Remove all stored entries.
    public func clear() {
        entries.removeAll()
    }

    // MARK: - Export

    /// Generate a file at a temporary URL in the given format.
    /// Returns the URL — pass it to `ShareLink`, `UIActivityViewController`, etc.
    public func exportURL(
        format: LogExportFormat = .txt,
        entries: [LogEntry]? = nil,
        sessionDate: Date? = nil
    ) async throws -> URL {
        let source = entries ?? self.entries
        let date = sessionDate ?? self.sessionDate
        let content: String
        switch format {
        case .txt:
            content = LogFormatter.formatExport(source, sessionDate: date)
        case .json:
            content = try LogFormatter.formatJSON(source)
        case .csv:
            content = LogFormatter.formatCSV(source)
        case .html:
            content = LogFormatter.formatHTML(source, sessionDate: date)
        }

        let filename = "SugarLogger-\(filenameDate()).\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Viewer

    /// Present the log viewer sheet synchronously (no `await` needed).
    /// Works together with the `.logViewer()` SwiftUI ViewModifier.
    nonisolated public func presentViewer() {
        Task { @MainActor in
            viewerState.isPresented = true
        }
    }
}

// MARK: - Private

private extension SugarLogger {

    func logIsolated(
        _ message: String,
        level: LogLevel,
        category: LogCategory,
        metadata: [(key: String, value: String)]
    ) {
        guard level >= minimumLevel else { return }
        if let allowed = enabledCategories, !allowed.contains(category) { return }

        let entry = LogEntry(
            level: level,
            category: category,
            message: message,
            metadata: metadata
        )
        enqueue(entry)
    }

    func logNetworkIsolated(
        method: String,
        url: URL?,
        requestHeaders: [(key: String, value: String)],
        requestBody: String?,
        statusCode: Int?,
        responseHeaders: [(key: String, value: String)],
        responseBody: String?,
        durationMs: Int?,
        error: Error?
    ) {
        let level: LogLevel
        let message: String

        if let error {
            level = .error
            message = error.localizedDescription
        } else {
            let code = statusCode ?? 0
            level = code >= 400 ? .error : .info
            let statusText = HTTPURLResponse.localizedString(forStatusCode: code).capitalized
            let durationStr = durationMs.map { "  ·  \($0)ms" } ?? ""
            message = "← \(code)  \(statusText)\(durationStr)"
        }

        guard level >= minimumLevel else { return }
        if let allowed = enabledCategories, !allowed.contains(.network) { return }

        let networkEntry: NetworkLogEntry
        if let code = statusCode, let ms = durationMs {
            networkEntry = NetworkLogEntry(
                method: method, url: url,
                requestHeaders: requestHeaders, requestBody: requestBody,
                statusCode: code,
                responseHeaders: responseHeaders, responseBody: responseBody,
                durationMs: ms
            )
        } else {
            networkEntry = NetworkLogEntry(
                method: method, url: url,
                requestHeaders: requestHeaders, requestBody: requestBody
            )
        }

        let entry = LogEntry(
            level: level,
            category: .network,
            message: message,
            networkEntry: networkEntry
        )
        enqueue(entry)
    }

    func enqueue(_ entry: LogEntry) {
        if entries.count >= maxEntries {
            entries.removeFirst(entries.count - maxEntries + 1)
        }
        entries.append(entry)
        continuation?.yield(.added(entry))
    }

    func filenameDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f.string(from: Date())
    }
}
