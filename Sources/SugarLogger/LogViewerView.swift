import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - View Modifier

public struct LogViewerModifier: ViewModifier {
    @ObservedObject private var state: LogViewerState

    public init(state: LogViewerState = SugarLogger.shared.viewerState) {
        self.state = state
    }

    public func body(content: Content) -> some View {
        content
            .sheet(isPresented: $state.isPresented) {
                LogViewerView()
            }
    }
}

public extension View {
    func logViewer(state: LogViewerState = SugarLogger.shared.viewerState) -> some View {
        modifier(LogViewerModifier(state: state))
    }
}

// MARK: - Design tokens

private enum LV {
    // Backgrounds — adapt to system color scheme
    #if canImport(UIKit)
    static let bg         = Color(uiColor: .systemBackground)
    static let surface    = Color(uiColor: .secondarySystemBackground)
    static let surfaceAlt = Color(uiColor: .tertiarySystemBackground)
    static let border     = Color(uiColor: .separator).opacity(0.5)
    // Text
    static let textPri    = Color(uiColor: .label)
    static let textSec    = Color(uiColor: .secondaryLabel)
    static let textTer    = Color(uiColor: .tertiaryLabel)
    #else
    static let bg         = Color(nsColor: .windowBackgroundColor)
    static let surface    = Color(nsColor: .controlBackgroundColor)
    static let surfaceAlt = Color(nsColor: .underPageBackgroundColor)
    static let border     = Color(nsColor: .separatorColor).opacity(0.5)
    static let textPri    = Color(nsColor: .labelColor)
    static let textSec    = Color(nsColor: .secondaryLabelColor)
    static let textTer    = Color(nsColor: .tertiaryLabelColor)
    #endif
}

// MARK: - LogViewerView

public struct LogViewerView: View {
    @State private var entries: [LogEntry] = []
    @State private var searchText: String = ""
    @State private var selectedLevel: LogLevel? = nil
    @State private var selectedCategory: LogCategory? = nil
    @State private var availableCategories: [LogCategory] = []
    @State private var showExportSheet: Bool = false
    @State private var exportOnlyFiltered: Bool = false
    @State private var isLive: Bool = true
    @State private var selectedEntryID: UUID? = nil

    @Environment(\.dismiss) private var dismiss

    private var filtered: [LogEntry] {
        entries.filter { e in
            let levelOK    = selectedLevel == nil || e.level >= selectedLevel!
            let categoryOK = selectedCategory == nil || e.category == selectedCategory
            let searchOK   = searchText.isEmpty ||
                e.message.localizedCaseInsensitiveContains(searchText) ||
                e.metadata.contains {
                    $0.key.localizedCaseInsensitiveContains(searchText) ||
                    $0.value.localizedCaseInsensitiveContains(searchText)
                }
            return levelOK && categoryOK && searchOK
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                LV.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    filterBar
                    logList
                }
            }
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LV.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar { toolbar }
            .searchable(text: $searchText, prompt: "Search…")
            .navigationDestination(item: $selectedEntryID) { id in
                if let entry = entries.first(where: { $0.id == id }) {
                    LogEntryDetailView(entry: entry, searchText: searchText)
                }
            }
            .sheet(isPresented: $showExportSheet) {
                ExportSheetView(
                    entries: exportOnlyFiltered ? filtered : entries,
                    filteredEntries: filtered,
                    exportOnlyFiltered: $exportOnlyFiltered
                )
                .presentationDetents([.medium, .large])
            }
        }
        .task {
            let existing = await SugarLogger.shared.allEntries()
            entries = existing
            refreshCategories()
            // Track ids already in the list so stream events for the same
            // entries (emitted between allEntries() and our first iteration)
            // are treated as replacements instead of duplicates.
            var knownIDs = Set(existing.map(\.id))
            for await event in SugarLogger.shared.stream {
                switch event {
                case .added(let entry):
                    if knownIDs.contains(entry.id) {
                        // Already loaded via allEntries() — just update in place.
                        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                            entries[idx] = entry
                        }
                    } else {
                        knownIDs.insert(entry.id)
                        entries.append(entry)
                        if !availableCategories.contains(entry.category) {
                            availableCategories.append(entry.category)
                        }
                    }
                case .replaced(let entry):
                    if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                        entries[idx] = entry
                    }
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                Image(systemName: "ladybug.fill")
                    .foregroundStyle(Color(hex: "#FF453A"))
                    .font(.system(size: 13, weight: .bold))
                Text("SugarLogger")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LV.textPri)
                Text("\(filtered.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(LV.border)
                    .foregroundStyle(LV.textSec)
                    .clipShape(Capsule())
            }
        }

        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LV.textSec)
                    .frame(width: 28, height: 28)
                    .background(LV.surfaceAlt)
                    .clipShape(Circle())
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showExportSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LV.textSec)
            }

            Button(role: .destructive) {
                Task {
                    await SugarLogger.shared.clear()
                    withAnimation { entries = []; availableCategories = [] }
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: "#FF453A").opacity(0.8))
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Level pills
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        levelPill(level)
                    }

                    // Separator
                    Rectangle()
                        .fill(LV.border)
                        .frame(width: 1, height: 16)
                        .padding(.horizontal, 2)

                    // Category pills
                    categoryPill(nil, label: "All")
                    ForEach(availableCategories, id: \.rawValue) { cat in
                        categoryPill(cat, label: cat.rawValue.uppercased())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            Rectangle()
                .fill(LV.border)
                .frame(height: 1)
        }
        .background(LV.surface)
    }

    private func levelPill(_ level: LogLevel) -> some View {
        let isSelected = selectedLevel == level
        let color = Color(hex: level.colorHex)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedLevel = isSelected ? nil : level
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                Text(level.rawValue)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isSelected ? color.opacity(0.15) : LV.surfaceAlt)
            .foregroundStyle(isSelected ? color : LV.textSec)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? color.opacity(0.4) : LV.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func categoryPill(_ category: LogCategory?, label: String) -> some View {
        let isSelected = selectedCategory == category
        let color = category.map { Color(hex: $0.colorHex) } ?? LV.textSec
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = isSelected ? nil : category
            }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(isSelected ? color.opacity(0.15) : LV.surfaceAlt)
                .foregroundStyle(isSelected ? color : LV.textSec)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? color.opacity(0.4) : LV.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log list

    private var logList: some View {
        Group {
            if filtered.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, entry in
                                LogRowView(entry: entry, searchText: searchText, index: filtered.count - idx)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedEntryID = entry.id }

                                if idx < filtered.count - 1 {
                                    Rectangle()
                                        .fill(LV.border.opacity(0.5))
                                        .frame(height: 1)
                                        .padding(.leading, 52)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .scrollContentBackground(.hidden)
                    .background(LV.bg)
                    .onChange(of: entries.count) { _, _ in
                        if isLive, let last = filtered.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(LV.textTer)
            Text(searchText.isEmpty ? "No logs yet" : "No results")
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(LV.textSec)
            if !searchText.isEmpty {
                Text("Try a different search term")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(LV.textTer)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func refreshCategories() {
        var seen = Set<LogCategory>()
        availableCategories = entries.compactMap { e -> LogCategory? in
            guard !seen.contains(e.category) else { return nil }
            seen.insert(e.category)
            return e.category
        }
    }
}

// MARK: - Log row

private struct LogRowView: View {
    let entry: LogEntry
    let searchText: String
    let index: Int

    private var levelColor: Color { Color(hex: entry.level.colorHex) }
    private var categoryColor: Color { Color(hex: entry.category.colorHex) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Level bar
            Rectangle()
                .fill(levelColor)
                .frame(width: 3)

            // Index
            Text("\(index)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(LV.textTer)
                .frame(width: 28)
                .padding(.top, 14)

            // Content
            VStack(alignment: .leading, spacing: 5) {
                // Top row: time + combined category·level badge
                HStack(spacing: 6) {
                    Text(LogFormatter.shortTime(entry.date))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(LV.textSec)

                    // Combined category · level badge
                    HStack(spacing: 4) {
                        Text(entry.category.rawValue.uppercased())
                            .foregroundStyle(categoryColor)
                        Text("·")
                            .foregroundStyle(LV.textTer)
                        Text(entry.level.rawValue)
                            .foregroundStyle(levelColor)
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(categoryColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(categoryColor.opacity(0.25), lineWidth: 1)
                    )

                    Spacer()
                }

                // Message
                HighlightedText(text: entry.message, highlight: searchText)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(LV.textPri)
                    .lineLimit(2)

                // First metadata pair
                if let first = entry.metadata.first {
                    HStack(spacing: 4) {
                        Text(first.key)
                            .foregroundStyle(LV.textTer)
                        Text("·")
                            .foregroundStyle(LV.textTer)
                        Text(first.value)
                            .foregroundStyle(LV.textSec)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, design: .monospaced))
                }
            }
            .padding(.vertical, 10)
            .padding(.trailing, 14)
            .padding(.leading, 6)

        }
        .background(LV.bg)
    }
}

// MARK: - Log entry detail

private struct LogEntryDetailView: View {
    let entry: LogEntry
    let searchText: String
    @State private var copied = false
    @State private var showExportSheet = false

    private var levelColor: Color { Color(hex: entry.level.colorHex) }
    private var categoryColor: Color { Color(hex: entry.category.colorHex) }

    var body: some View {
        ZStack {
            LV.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header card
                    headerCard
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    // For non-network entries show the message as a card.
                    // For network entries the message is redundant — REQUEST/RESPONSE cover it.
                    if entry.networkEntry == nil {
                        sectionCard(title: "MESSAGE") {
                            HighlightedText(text: entry.message, highlight: searchText)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(LV.textPri)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // Metadata — skip for network entries (url/duration already in REQUEST/RESPONSE)
                    if !entry.metadata.isEmpty && entry.networkEntry == nil {
                        sectionCard(title: "DETAILS") {
                            VStack(spacing: 8) {
                                ForEach(entry.metadata, id: \.key) { pair in
                                    metadataRow(key: pair.key, value: pair.value)
                                }
                            }
                        }
                    }

                    // Network detail cards
                    if let net = entry.networkEntry {
                        networkDetailCards(net)
                    }

                    // Copy button
                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = LogFormatter.formatBlock(entry)
                        #endif
                        withAnimation { copied = true }
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            withAnimation { copied = false }
                        }
                    } label: {
                        HStack {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied" : "Copy Entry")
                        }
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(copied ? Color(hex: "#30D158") : LV.textSec)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(LV.surfaceAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(copied ? Color(hex: "#30D158").opacity(0.3) : LV.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                }
                .padding(.bottom, 20)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Log Entry")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(LV.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showExportSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LV.textSec)
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheetView(
                entries: [entry],
                filteredEntries: [entry],
                exportOnlyFiltered: .constant(false)
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var headerCard: some View {
        HStack(spacing: 12) {
            // Level indicator strip
            RoundedRectangle(cornerRadius: 2)
                .fill(levelColor)
                .frame(width: 4)
                .frame(height: 52)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(entry.level.rawValue)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(levelColor.opacity(0.15))
                        .foregroundStyle(levelColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text(entry.category.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(categoryColor.opacity(0.12))
                        .foregroundStyle(categoryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Text(LogFormatter.shortTime(entry.date))
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(LV.textSec)
            }

            Spacer()

            Image(systemName: entry.level.symbolName)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(levelColor.opacity(0.6))
        }
        .padding(14)
        .background(LV.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(levelColor.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func sectionCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(LV.textTer)
                .kerning(1.5)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LV.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(LV.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func metadataRow(key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(LV.textTer)
            HighlightedText(text: value, highlight: searchText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(LV.textSec)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(LV.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(LV.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func networkDetailCards(_ net: NetworkLogEntry) -> some View {
        // Request info
        sectionCard(title: "REQUEST") {
            VStack(spacing: 8) {
                metadataRow(key: "method", value: net.method)
                if let url = net.url {
                    metadataRow(key: "url", value: url.absoluteString)
                }
                if !net.requestHeaders.isEmpty {
                    metadataRow(
                        key: "headers",
                        value: net.requestHeaders.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
                    )
                }
                if let body = net.requestBody {
                    metadataRow(key: "body", value: body)
                }
            }
        }

        // Response info
        sectionCard(title: "RESPONSE") {
            VStack(spacing: 8) {
                if let code = net.statusCode {
                    let statusText = HTTPURLResponse.localizedString(forStatusCode: code).capitalized
                    metadataRow(key: "status", value: "\(code) \(statusText)")
                }
                if let ms = net.durationMs {
                    metadataRow(key: "duration", value: "\(ms)ms")
                }
                if !net.responseHeaders.isEmpty {
                    metadataRow(
                        key: "headers",
                        value: net.responseHeaders.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
                    )
                }
                if let body = net.responseBody {
                    metadataRow(key: "body", value: body)
                }
            }
        }
    }
}

// MARK: - Export sheet

struct ExportSheetView: View {
    let entries: [LogEntry]
    let filteredEntries: [LogEntry]
    @Binding var exportOnlyFiltered: Bool

    @State private var selectedFormat: LogExportFormat = .txt
    @State private var exportURL: URL? = nil
    @State private var showShareSheet: Bool = false
    @State private var showDocumentPicker: Bool = false
    @State private var copiedToClipboard: Bool = false
    @State private var errorMessage: String? = nil

    private var exportEntries: [LogEntry] { exportOnlyFiltered ? filteredEntries : entries }

    var body: some View {
        NavigationStack {
            ZStack {
                LV.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Format picker
                        sectionBlock(title: "FORMAT") {
                            VStack(spacing: 1) {
                                ForEach(Array(LogExportFormat.allCases.enumerated()), id: \.element) { idx, format in
                                    formatRow(format: format, isLast: idx == LogExportFormat.allCases.count - 1)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(LV.border, lineWidth: 1)
                            )
                        }

                        // Scope — hidden when there is only one entry
                        if entries.count > 1 {
                            sectionBlock(title: "SCOPE") {
                                VStack(spacing: 1) {
                                    scopeRow(
                                        title: "All entries",
                                        subtitle: "\(entries.count) total",
                                        isSelected: !exportOnlyFiltered
                                    ) { exportOnlyFiltered = false }

                                    Rectangle().fill(LV.border).frame(height: 1)

                                    scopeRow(
                                        title: "Filtered only",
                                        subtitle: "\(filteredEntries.count) visible",
                                        isSelected: exportOnlyFiltered
                                    ) { exportOnlyFiltered = true }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(LV.border, lineWidth: 1)
                                )
                            }
                        }

                        // Actions
                        sectionBlock(title: "EXPORT") {
                            VStack(spacing: 8) {
                                actionButton(
                                    icon: "square.and.arrow.up",
                                    title: "Share",
                                    accent: Color(hex: "#0A84FF"),
                                    disabled: exportEntries.isEmpty
                                ) { generate() }

                                actionButton(
                                    icon: copiedToClipboard ? "checkmark" : "doc.on.clipboard",
                                    title: copiedToClipboard ? "Copied!" : "Copy to Clipboard",
                                    accent: copiedToClipboard ? Color(hex: "#30D158") : Color(hex: "#0A84FF"),
                                    disabled: exportEntries.isEmpty
                                ) { copyToClipboard() }

                                actionButton(
                                    icon: "folder",
                                    title: "Save to Files",
                                    accent: Color(hex: "#0A84FF"),
                                    disabled: exportEntries.isEmpty
                                ) { Task { await saveToFiles() } }
                            }
                        }

                        if let err = errorMessage {
                            Text(err)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color(hex: "#FF453A"))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(hex: "#FF453A").opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 16)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Export")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LV.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareActivityView(items: [url])
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            if let url = exportURL {
                DocumentPickerView(url: url)
                    .ignoresSafeArea()
            }
        }
        #endif
    }

    @ViewBuilder
    private func sectionBlock(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(LV.textTer)
                .kerning(1.5)
                .padding(.horizontal, 4)
            content()
        }
        .padding(.horizontal, 16)
    }

    private func formatRow(format: LogExportFormat, isLast: Bool) -> some View {
        let isSelected = selectedFormat == format
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedFormat = format }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: formatIcon(format))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Color(hex: "#0A84FF") : LV.textSec)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(format.rawValue)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSelected ? LV.textPri : LV.textSec)
                    Text(format.description)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(LV.textTer)
                        .lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: "#0A84FF"))
                        .font(.system(size: 16))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? Color(hex: "#0A84FF").opacity(0.08) : LV.surface)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(LV.border).frame(height: 1).padding(.leading, 46)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func scopeRow(title: String, subtitle: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? LV.textPri : LV.textSec)
                    Text(subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(LV.textTer)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: "#0A84FF"))
                        .font(.system(size: 16))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? Color(hex: "#0A84FF").opacity(0.08) : LV.surface)
        }
        .buttonStyle(.plain)
    }

    private func actionButton(icon: String, title: String, accent: Color, disabled: Bool, action: @escaping () -> Void) -> some View {
        ActionButtonRow(icon: icon, title: title, accent: accent, disabled: disabled, action: action)
    }

    private func formatIcon(_ format: LogExportFormat) -> String {
        switch format {
        case .txt:  return "doc.text"
        case .json: return "curlybraces"
        case .csv:  return "tablecells"
        case .html: return "globe"
        }
    }

    private func generate() {
        errorMessage = nil
        Task {
            do {
                let url = try await SugarLogger.shared.exportURL(format: selectedFormat, entries: exportEntries)
                exportURL = url
                showShareSheet = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func copyToClipboard() {
        Task {
            let text: String
            switch selectedFormat {
            case .txt:  text = LogFormatter.formatExport(exportEntries)
            case .csv:  text = LogFormatter.formatCSV(exportEntries)
            case .json: text = (try? LogFormatter.formatJSON(exportEntries)) ?? ""
            case .html: text = LogFormatter.formatHTML(exportEntries)
            }
            #if canImport(UIKit)
            UIPasteboard.general.string = text
            #endif
            withAnimation { copiedToClipboard = true }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { copiedToClipboard = false }
        }
    }

    private func saveToFiles() async {
        do {
            let url = try await SugarLogger.shared.exportURL(format: selectedFormat, entries: exportEntries)
            exportURL = url
            showDocumentPicker = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}



// MARK: - UIActivityViewController wrapper

#if canImport(UIKit)
struct ShareActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct DocumentPickerView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url])
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
#endif

// MARK: - Action button row

/// A tappable row that tracks its own pressed state without relying on
/// SwiftUI's Button hit-testing (which can bleed into adjacent rows).
private struct ActionButtonRow: View {
    let icon: String
    let title: String
    let accent: Color
    let disabled: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(disabled ? LV.textTer : LV.textPri)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(isPressed ? LV.surfaceAlt : LV.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(LV.border, lineWidth: 1)
        )
        .opacity(disabled ? 0.4 : 1)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !disabled { isPressed = true } }
                .onEnded { value in
                    isPressed = false
                    // Only fire if the touch ended inside the view (no drag)
                    if !disabled, abs(value.translation.width) < 10, abs(value.translation.height) < 10 {
                        action()
                    }
                }
        )
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .allowsHitTesting(!disabled)
    }
}

// MARK: - Highlighted text view

private struct HighlightedText: View {
    let text: String
    let highlight: String

    var body: some View {
        if highlight.isEmpty {
            Text(text)
        } else {
            Text(makeAttributed())
        }
    }

    private func makeAttributed() -> AttributedString {
        var attributed = AttributedString(text)
        let lower = text.lowercased()
        let query = highlight.lowercased()
        var start = lower.startIndex
        while let range = lower.range(of: query, range: start..<lower.endIndex) {
            if let attrFrom = AttributedString.Index(range.lowerBound, within: attributed),
               let attrTo   = AttributedString.Index(range.upperBound,   within: attributed) {
                attributed[attrFrom..<attrTo].backgroundColor = .yellow.withAlphaComponent(0.7)
                attributed[attrFrom..<attrTo].foregroundColor = .black
            }
            start = range.upperBound
        }
        return attributed
    }
}

// MARK: - Color from hex

extension Color {
    init(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let val = UInt64(h, radix: 16) ?? 0
        let r = Double((val >> 16) & 0xFF) / 255
        let g = Double((val >> 8)  & 0xFF) / 255
        let b = Double(val         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
