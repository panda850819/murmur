import SwiftUI
import AppKit
import MurmurCore

/// App-side deep links into the two System Settings panes. Lives here (not in
/// `MurmurCore`) because opening Settings is an `NSWorkspace` UI action.
enum PermissionSettings {
    static func openAccessibility() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoring() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

@main
struct MurmurApp: App {
    var body: some Scene {
        WindowGroup("Murmur") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @StateObject private var dictation = DictationCoordinator.makeDefault()
    @StateObject private var hotkey = HotKeyBridge(
        monitor: GlobalHotKeyMonitor(),
        probe: RealPermissionProbe()
    )
    /// Shared correction store (A' + C). Drives the on-device proper-noun
    /// correction the coordinator applies, AND the one-tap capture form below.
    /// One instance, injected into the coordinator in `.onAppear`.
    @StateObject private var corrections = CorrectionStore.makeDefault()
    /// Local dictation history + derived stats (M5). One instance: the
    /// coordinator appends to it, the History section below renders it.
    @StateObject private var history = HistoryStore.makeDefault()

    /// One-tap correction form state (C).
    @State private var showCorrection = false
    /// History section disclosure state (M5). Collapsed by default — the
    /// dictation controls stay the visual focus.
    @State private var showHistory = false
    @State private var heardText = ""
    @State private var intendedText = ""

    /// 翻譯 mode's output language. Persisted here (UI concern) and pushed
    /// into the coordinator, which is AppKit/SwiftUI-free.
    @AppStorage("targetLanguage") private var targetLanguage = "English (US)"
    private static let targetLanguages = [
        "English (US)", "繁體中文", "日本語", "한국어", "Español", "Français", "Deutsch",
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text("Murmur")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("v\(Murmur.version)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                Task { await dictation.toggle() }
            } label: {
                Text(dictation.phase == .recording ? "Stop" : "Record")
                    .frame(minWidth: 120)
            }
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(dictation.phase == .transcribing)

            VStack(spacing: 2) {
                Text("Hold Right ⌘ anywhere to dictate")
                if dictation.canChat {
                    Text("+ Right ⇧ to translate · tap / while holding to ask")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            if dictation.canEnhance {
                Toggle("Clean up with AI", isOn: $dictation.enhanceEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
            }

            if dictation.canChat {
                Picker("Translate to", selection: $targetLanguage) {
                    ForEach(Self.targetLanguages, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
                .onChange(of: targetLanguage) { _, newValue in
                    dictation.targetLanguage = newValue
                }
            }

            if !hotkey.allPermissionsGranted {
                VStack(spacing: 6) {
                    Text("Murmur needs two permissions. Enable both, then "
                        + "quit and reopen the app:")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(hotkey.inputMonitoringGranted ? "✓" : "✗") "
                        + "Input Monitoring — global hotkey")
                        .font(.caption)
                        .foregroundStyle(hotkey.inputMonitoringGranted
                            ? Color.secondary : Color.orange)
                    Text("\(hotkey.accessibilityGranted ? "✓" : "✗") "
                        + "Accessibility — auto-paste")
                        .font(.caption)
                        .foregroundStyle(hotkey.accessibilityGranted
                            ? Color.secondary : Color.orange)
                    HStack(spacing: 8) {
                        Button("Input Monitoring") {
                            PermissionSettings.openInputMonitoring()
                        }
                        Button("Accessibility") {
                            PermissionSettings.openAccessibility()
                        }
                        Button("Re-check") { hotkey.retry() }
                    }
                    .controlSize(.small)
                }
            }

            if dictation.phase == .transcribing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Transcribing…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let text = dictation.transcript {
                ScrollView {
                    Text(text.isEmpty ? "(no speech detected)" : text)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 160)

                correctionCapture
            }
            if let url = dictation.lastSavedURL {
                Text("Saved: \(url.lastPathComponent)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let err = dictation.errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            historySection
        }
        .padding(40)
        .frame(minWidth: 360, minHeight: 240)
        .onAppear {
            hotkey.attach(to: dictation)
            dictation.corrector = corrections
            dictation.selectionReader = AXSelectionReader()
            dictation.history = history
            dictation.targetLanguage = targetLanguage
        }
    }

    /// Collapsible dictation history (M5): the last 20 records as
    /// date · mode tag · first line, a Clear button, and a one-line stats
    /// footnote. 20 keeps the window compact; the store still holds 200.
    @ViewBuilder
    private var historySection: some View {
        VStack(spacing: 6) {
            DisclosureGroup(isExpanded: $showHistory) {
                VStack(alignment: .leading, spacing: 4) {
                    if history.records.isEmpty {
                        Text("No dictations yet")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(history.records.prefix(20)) { record in
                            HStack(spacing: 6) {
                                Text(record.date, format: .dateTime.month().day().hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(record.mode)
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                                Text(firstLine(of: record.text))
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        Button("Clear") { history.clear() }
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            } label: {
                Text("History")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // M5 stats: derived live from the same records the list shows,
            // so the numbers can never disagree with the visible history.
            // "(last 200)" because the store caps at `HistoryStore.capacity`
            // — these are rolling-window numbers, not lifetime totals, and
            // the copy must not promise more than the data covers.
            let stats = history.stats
            Text("\(stats.dictations) dictations · \(stats.words) words · "
                + "~\(String(format: "%.0f", stats.estMinutesSaved)) min saved (last 200)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: 320)
    }

    /// First line only — a multi-paragraph dictation must not blow up a
    /// single history row.
    private func firstLine(of text: String) -> String {
        text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? text
    }

    /// Mirrors `CorrectionStore.captureCorrection`'s accept rule (same trim
    /// charset, reject case-only-equal) so Save is disabled rather than a
    /// dead tap that silently no-ops.
    private var canSaveCorrection: Bool {
        let h = heardText.trimmingCharacters(in: .whitespacesAndNewlines)
        let i = intendedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !h.isEmpty && !i.isEmpty && h.lowercased() != i.lowercased()
    }

    /// One-tap correction-capture loop (C): teach murmur a {heard → intended}
    /// pair. The pair persists, fixes that exact mishearing next time, and adds
    /// its `intended` to the fuzzy term list so near-misses are caught too.
    @ViewBuilder
    private var correctionCapture: some View {
        VStack(spacing: 6) {
            Button {
                showCorrection.toggle()
            } label: {
                Label("Fix a word", systemImage: "pencil")
            }
            .buttonStyle(.link)
            .controlSize(.small)

            if showCorrection {
                HStack(spacing: 6) {
                    TextField("misheard", text: $heardText)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField("correct", text: $intendedText)
                    Button("Save") {
                        if corrections.captureCorrection(heard: heardText, intended: intendedText) {
                            heardText = ""
                            intendedText = ""
                            showCorrection = false
                        }
                    }
                    .disabled(!canSaveCorrection)
                }
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)

                if !corrections.pairs.isEmpty {
                    Text("\(corrections.pairs.count) correction"
                        + (corrections.pairs.count == 1 ? "" : "s") + " saved")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
