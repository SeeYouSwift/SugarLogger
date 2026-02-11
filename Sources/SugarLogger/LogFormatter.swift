import Foundation

/// Converts log entries into human-readable plain-text output.
///
/// Each entry is a flat block separated by a divider:
/// ```
/// ----------------------------------------------
/// 15:42  NETWORK  INFO
/// <- 200  Ok  ·  327ms
///
/// REQUEST
///   GET  https://api.example.com/dogs
///
/// RESPONSE
///   200  Ok  ·  327ms
///   {
///     "breeds": ["husky"]
///   }
/// ```
public struct LogFormatter: Sendable {

    // MARK: - Constants

    private static let divider = String(repeating: "-", count: 50)

    // MARK: - Public API

    /// Render a complete TXT export with session header + all entries.
    public static func formatExport(_ entries: [LogEntry], sessionDate: Date = Date()) -> String {
        var lines: [String] = []

        lines.append("SugarLogger  |  \(sessionDateString(sessionDate))  |  \(entries.count) entries")
        lines.append(divider)

        for entry in entries {
            lines.append(formatBlock(entry))
            lines.append(divider)
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Render a single entry as a flat text block (no trailing divider).
    public static func formatBlock(_ entry: LogEntry) -> String {
        var lines: [String] = []

        // Header: time  CATEGORY  LEVEL
        lines.append("\(timeString(entry.date))  \(entry.category.rawValue.uppercased())  \(entry.level.rawValue)")

        // Message
        lines.append(entry.message)

        // Metadata (non-network entries only)
        if entry.networkEntry == nil, !entry.metadata.isEmpty {
            lines.append("")
            for pair in entry.metadata {
                lines.append("  \(pair.key): \(pair.value)")
            }
        }

        // Network detail
        if let net = entry.networkEntry {
            lines.append("")
            appendNetworkSection(&lines, net: net)
        }

        return lines.joined(separator: "\n")
    }

    /// Short time string for the log viewer UI.
    public static func shortTime(_ date: Date) -> String {
        timeString(date)
    }

    // MARK: - Internal helpers (accessible from extensions)

    static func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func sessionDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }
}

// MARK: - Private helpers

private extension LogFormatter {

    /// Render a network REQUEST + RESPONSE block (flat, indented).
    static func appendNetworkSection(_ lines: inout [String], net: NetworkLogEntry) {
        // REQUEST
        lines.append("REQUEST")
        lines.append("  \(net.method)  \(net.url?.absoluteString ?? "-")")
        for h in net.requestHeaders {
            lines.append("  \(h.key): \(h.value)")
        }
        if let body = net.requestBody, !body.isEmpty {
            lines.append("")
            for line in prettyLines(body, indent: "  ") { lines.append(line) }
        }

        // RESPONSE (only if status code is present)
        if let code = net.statusCode {
            lines.append("")
            lines.append("RESPONSE")
            let statusText = HTTPURLResponse.localizedString(forStatusCode: code).capitalized
            let durationStr = net.durationMs.map { "  ·  \($0)ms" } ?? ""
            lines.append("  \(code)  \(statusText)\(durationStr)")
            for h in net.responseHeaders {
                lines.append("  \(h.key): \(h.value)")
            }
            if let body = net.responseBody, !body.isEmpty {
                lines.append("")
                for line in prettyLines(body, indent: "  ") { lines.append(line) }
            }
        }
    }

    /// Try to pretty-print JSON; fall back to the raw string.
    /// Each output line is prefixed with `indent`.
    static func prettyLines(_ text: String, indent: String) -> [String] {
        let pretty: String
        if let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let prettyStr = String(data: prettyData, encoding: .utf8) {
            pretty = prettyStr
        } else {
            pretty = text
        }
        return pretty.components(separatedBy: "\n").map { indent + $0 }
    }
}

// MARK: - JSON export helper

extension LogFormatter {
    /// Encode entries as a JSON array string.
    public static func formatJSON(_ entries: [LogEntry]) throws -> String {
        let iso = ISO8601DateFormatter()
        let dicts: [[String: Any]] = entries.map { e in
            var d: [String: Any] = [
                "id":       e.id.uuidString,
                "date":     iso.string(from: e.date),
                "level":    e.level.rawValue,
                "category": e.category.rawValue,
                "message":  e.message
            ]
            if !e.metadata.isEmpty {
                var meta: [String: String] = [:]
                for pair in e.metadata { meta[pair.key] = pair.value }
                d["metadata"] = meta
            }
            if let net = e.networkEntry {
                var req: [String: Any] = ["method": net.method]
                if let url = net.url { req["url"] = url.absoluteString }
                if !net.requestHeaders.isEmpty {
                    req["headers"] = net.requestHeaders.map { ["\($0.key)": $0.value] }
                }
                if let body = net.requestBody { req["body"] = jsonObjectOrString(body) }

                var netDict: [String: Any] = ["request": req]

                if let code = net.statusCode {
                    var res: [String: Any] = ["status": code]
                    if let ms = net.durationMs { res["duration_ms"] = ms }
                    if !net.responseHeaders.isEmpty {
                        res["headers"] = net.responseHeaders.map { ["\($0.key)": $0.value] }
                    }
                    if let body = net.responseBody { res["body"] = jsonObjectOrString(body) }
                    netDict["response"] = res
                }
                d["network"] = netDict
            }
            return d
        }
        let data = try JSONSerialization.data(withJSONObject: dicts, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// Parse a string as JSON if possible, otherwise return it as-is.
    private static func jsonObjectOrString(_ s: String) -> Any {
        if let data = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) { return obj }
        return s
    }
}

// MARK: - CSV export helper

extension LogFormatter {
    /// Encode entries as RFC-4180 CSV.
    public static func formatCSV(_ entries: [LogEntry]) -> String {
        let header = "id,date,level,category,message,metadata,method,url,status,duration_ms,request_headers,request_body,response_headers,response_body"
        var rows: [String] = [header]
        let iso = ISO8601DateFormatter()
        for e in entries {
            let meta = e.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            let net = e.networkEntry
            rows.append([
                e.id.uuidString,
                iso.string(from: e.date),
                e.level.rawValue,
                e.category.rawValue,
                csvEscape(e.message),
                csvEscape(meta),
                csvEscape(net?.method ?? ""),
                csvEscape(net?.url?.absoluteString ?? ""),
                net?.statusCode.map { "\($0)" } ?? "",
                net?.durationMs.map { "\($0)" } ?? "",
                csvEscape(net?.requestHeaders.map { "\($0.key): \($0.value)" }.joined(separator: "; ") ?? ""),
                csvEscape(net?.requestBody ?? ""),
                csvEscape(net?.responseHeaders.map { "\($0.key): \($0.value)" }.joined(separator: "; ") ?? ""),
                csvEscape(net?.responseBody ?? "")
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private static func csvEscape(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

// MARK: - HTML export helper

extension LogFormatter {
    /// Encode entries as a styled HTML page.
    public static func formatHTML(_ entries: [LogEntry], sessionDate: Date = Date()) -> String {
        let rows = entries.map { e -> String in
            let messageCell: String
            if let net = e.networkEntry {
                messageCell = htmlNetworkCell(net)
            } else {
                let meta = e.metadata
                    .map { "<div class='kv'><span class='k'>\(htmlEscape($0.key))</span><span class='v'>\(htmlEscape($0.value))</span></div>" }
                    .joined()
                messageCell = "<span class='msg'>\(htmlEscape(e.message))</span>\(meta)"
            }
            return """
            <tr>
              <td><span class='badge level' style='color:\(e.level.colorHex);border-color:\(e.level.colorHex)40'>\(e.level.rawValue)</span></td>
              <td><span class='badge cat' style='color:\(e.category.colorHex);border-color:\(e.category.colorHex)40'>\(e.category.rawValue)</span></td>
              <td class='time'>\(timeString(e.date))</td>
              <td>\(messageCell)</td>
            </tr>
            """
        }.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <title>SugarLogger · \(sessionDateString(sessionDate))</title>
          <style>
            *, *::before, *::after { box-sizing: border-box; }
            body   { font-family: ui-monospace, 'SF Mono', Menlo, monospace; font-size: 12px; background: #1c1c1e; color: #e5e5ea; margin: 0; padding: 24px; }
            h1     { color: #ebebf5; font-size: 14px; font-weight: 600; margin: 0 0 16px; }
            table  { border-collapse: collapse; width: 100%; }
            th     { background: #2c2c2e; padding: 7px 12px; text-align: left; color: #636366; font-size: 10px; letter-spacing: 0.8px; }
            td     { padding: 8px 12px; border-bottom: 1px solid #2c2c2e; vertical-align: top; }
            tr:hover td { background: #242426; }
            .time  { color: #636366; white-space: nowrap; }
            .badge { font-size: 10px; font-weight: 700; padding: 2px 6px; border-radius: 4px; border: 1px solid; white-space: nowrap; }
            .msg   { display: block; margin-bottom: 4px; }
            .kv    { display: flex; gap: 8px; margin-top: 3px; }
            .k     { color: #636366; min-width: 80px; }
            .v     { color: #aeaeb2; word-break: break-all; }
            .section-title { font-size: 10px; letter-spacing: 0.8px; color: #636366; margin: 6px 0 3px; }
            .net-row { display: flex; gap: 8px; margin: 2px 0; }
            .net-k  { color: #636366; min-width: 100px; }
            .net-v  { color: #aeaeb2; word-break: break-all; }
            pre    { margin: 4px 0; white-space: pre-wrap; word-break: break-all; color: #aeaeb2; background: #2c2c2e; padding: 8px; border-radius: 6px; font-size: 11px; }
          </style>
        </head>
        <body>
        <h1>SugarLogger · \(sessionDateString(sessionDate)) · \(entries.count) entries</h1>
        <table>
          <thead><tr><th>LEVEL</th><th>CATEGORY</th><th>TIME</th><th>MESSAGE</th></tr></thead>
          <tbody>
        \(rows)
          </tbody>
        </table>
        </body>
        </html>
        """
    }

    private static func htmlNetworkCell(_ net: NetworkLogEntry) -> String {
        var html = ""

        // Summary line
        let statusStr = net.statusCode.map { code in
            let text = HTTPURLResponse.localizedString(forStatusCode: code).capitalized
            let color = code < 400 ? "#30D158" : "#FF453A"
            return "<span style='color:\(color);font-weight:600'>\(code) \(htmlEscape(text))</span>"
        } ?? ""
        let durationStr = net.durationMs.map { " · \($0)ms" } ?? ""
        html += "<span class='msg'>\(htmlEscape(net.method)) \(htmlEscape(net.url?.absoluteString ?? "-")) \(statusStr)\(htmlEscape(durationStr))</span>"

        // REQUEST
        html += "<div class='section-title'>REQUEST</div>"
        for h in net.requestHeaders {
            html += "<div class='net-row'><span class='net-k'>\(htmlEscape(h.key))</span><span class='net-v'>\(htmlEscape(h.value))</span></div>"
        }
        if let body = net.requestBody, !body.isEmpty {
            html += "<pre>\(htmlEscape(prettyJSON(body)))</pre>"
        }

        // RESPONSE
        if net.statusCode != nil {
            html += "<div class='section-title'>RESPONSE</div>"
            for h in net.responseHeaders {
                html += "<div class='net-row'><span class='net-k'>\(htmlEscape(h.key))</span><span class='net-v'>\(htmlEscape(h.value))</span></div>"
            }
            if let body = net.responseBody, !body.isEmpty {
                html += "<pre>\(htmlEscape(prettyJSON(body)))</pre>"
            }
        }

        return html
    }

    private static func prettyJSON(_ s: String) -> String {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else { return s }
        return str
    }

    private static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
