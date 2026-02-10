# SugarLogger

A flexible, thread-safe logger for Swift with a built-in SwiftUI viewer, live stream, multi-format export, and first-class network logging support.

## Features

- **Actor-based** — `SugarLogger` is a Swift actor; thread-safe with no locks
- **Open categories** — built-in `.network`, `.error`, `.retry`, `.event`; add your own with `LogCategory("payment")`
- **Severity levels** — `.debug`, `.info`, `.warning`, `.error`; set `minimumLevel` to filter noise
- **Live stream** — subscribe to `AsyncStream<LogEntry>` for real-time updates
- **LogViewerView** — SwiftUI sheet with live log list, search with highlight, category + level filters, tap-to-detail
- **Network detail view** — tap any network entry to see REQUEST / RESPONSE with headers and body
- **Dark mode** — viewer adapts to the system color scheme automatically
- **Export sheet** — choose format, scope, and action inside the app
- **Four export formats** — TXT, JSON, CSV, HTML
- **Extra export actions** — Copy to Clipboard, Save to Files, Send by Email

## Requirements

- iOS 18+ / macOS 15+
- Swift 6+

## Installation

### Swift Package Manager

**Via Xcode:** File → Add Package Dependencies → enter the repository URL.

**Via `Package.swift`:**
```swift
dependencies: [
    .package(url: "https://github.com/SeeYouSwift/SugarLogger", from: "1.0.0")
],
targets: [
    .target(name: "YourTarget", dependencies: ["SugarLogger"])
]
```

---

## Quick Start

### 1. Log events

```swift
import SugarLogger

// Fire-and-forget — no Task, no await needed:
SugarLogger.shared.log("User tapped checkout", category: .event)
SugarLogger.shared.log("Token missing", level: .error, category: .error,
    metadata: [("url", "https://api.example.com/pay"), ("reason", "timeout")])
```

### 2. Attach the viewer to your root view

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .logViewer()   // one line
        }
    }
}
```

### 3. Open the viewer from anywhere

```swift
// On a debug button tap (no await needed):
SugarLogger.shared.presentViewer()
```

---

## Network Logging

### Option A — `logNetwork` (any HTTP client)

Log any HTTP transaction without depending on SugarNetwork. All parameters except `method` and `url` are optional.

```swift
// Successful response
SugarLogger.shared.logNetwork(
    method: "GET",
    url: URL(string: "https://api.example.com/users"),
    statusCode: 200,
    durationMs: 320,
    responseBody: jsonString
)

// With request and response headers + bodies
SugarLogger.shared.logNetwork(
    method: "POST",
    url: url,
    requestHeaders: [("Content-Type", "application/json")],
    requestBody: #"{"name":"Alice"}"#,
    statusCode: 201,
    responseHeaders: [("X-Request-Id", "abc123")],
    responseBody: #"{"id":42}"#,
    durationMs: 140
)

// Failed request
SugarLogger.shared.logNetwork(
    method: "GET",
    url: url,
    error: URLError(.notConnectedToInternet)
)
```

In the log viewer, tapping a network entry shows two expanded sections:

- **REQUEST** — method, URL, headers, body
- **RESPONSE** — status code, duration, headers, body

### Option B — `NetworkEventDelegate` (SugarNetwork)

If you use SugarNetwork, wire logging via `NetworkLoggerAdapter`. Neither library depends on the other — the adapter lives in your app or feature module.

```swift
// In your app or feature module (imports both SugarNetwork and SugarLogger):
import SugarNetwork
import SugarLogger

let networkService = SugarNetwork(
    retryPolicy: .default,
    eventDelegate: NetworkLoggerAdapter(logger: SugarLogger.shared)
)
```

`NetworkLoggerAdapter` conforms to `NetworkEventDelegate` and calls `SugarLogger` automatically after every request.

---

## LogViewerView

```swift
// Attach to root view (recommended):
ContentView().logViewer()

// Custom logger instance:
ContentView().logViewer(state: myLogger.viewerState)

// Trigger programmatically:
SugarLogger.shared.presentViewer()
```

### Features

- **Live updates** — new entries appear instantly via `AsyncStream`
- **Search** — filters by message and metadata; highlights matches in yellow
- **Filter pills** — filter by category or minimum level
- **Combined badge** — each row shows `CATEGORY · LEVEL` in a single chip
- **Tap a row** — opens detail view with full data and a Copy button
- **Network detail** — REQUEST / RESPONSE sections with headers and body
- **Clear** — removes all in-memory entries
- **Export** — opens the export sheet

---

## Export Sheet

Tap the share icon in the viewer toolbar.

### Formats

| Format | Description |
|--------|-------------|
| **TXT** | Readable block format, one divider per entry |
| **JSON** | Array of objects — machine-readable |
| **CSV** | Spreadsheet-friendly, one row per entry |
| **HTML** | Styled table, opens in Safari |

### Actions

| Action | Description |
|--------|-------------|
| **Share / Save File** | System activity sheet |
| **Copy to Clipboard** | Copies selected format to clipboard |
| **Save to Files** | Document picker |
| **Send by Email** | Share extension |

Toggle **"Filtered only"** to export only what's currently visible.

---

## Categories

```swift
// Built-in:
.network   // teal
.error     // red
.retry     // orange
.event     // purple

// Custom (add anywhere in your codebase):
extension LogCategory {
    static let payment   = LogCategory("payment")
    static let analytics = LogCategory("analytics")
    static let auth      = LogCategory("auth")
}

SugarLogger.shared.log("Token refreshed", category: .auth)
```

Custom categories get a deterministic color from their name hash.

---

## Configuration

```swift
let logger = SugarLogger.shared

// Only record warnings and above:
logger.minimumLevel = .warning

// Only record specific categories:
logger.enabledCategories = [.network, .error]

// Adjust ring-buffer size (default: 2000):
logger.maxEntries = 5000
```

*(Properties are actor-isolated — set from an async context or wrap in `Task {}`)*

---

## API Reference

### `SugarLogger` — actor

| Method / Property | Description |
|-------------------|-------------|
| `log(_:level:category:metadata:)` | Fire-and-forget log entry |
| `logNetwork(method:url:...:)` | Fire-and-forget network entry with REQUEST / RESPONSE detail |
| `entries(level:category:)` | Retrieve stored entries with optional filter |
| `entries(matching:)` | Full-text search across message + metadata |
| `exportURL(format:entries:)` | Generate a file and return its temporary URL |
| `presentViewer()` | Trigger the log viewer sheet (no await needed) |
| `clear()` | Remove all in-memory entries |
| `stream` | `AsyncStream<LogEntry>` for live subscription |
| `minimumLevel` | Drop entries below this level |
| `enabledCategories` | Whitelist of recorded categories (`nil` = all) |
| `maxEntries` | Ring-buffer size (default: 2000) |

### `LogLevel`

`debug` · `info` · `warning` · `error` — `Comparable`, use `minimumLevel` to threshold

### `LogCategory`

Open struct — extend with your own static constants.
Built-in: `.network` · `.error` · `.retry` · `.event`

### `LogExportFormat`

`TXT` · `JSON` · `CSV` · `HTML`
