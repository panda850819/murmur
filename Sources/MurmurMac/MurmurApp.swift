import SwiftUI
import AppKit
import ApplicationServices
import MurmurCore

/// Owns the global hotkey monitor and bridges its press/release events into
/// the `DictationCoordinator`. Press/release are serialised through a single
/// task chain so a fast tap can't run the release's `toggle()` before the
/// press's `toggle()` has finished establishing the recording state.
@MainActor
final class HotKeyBridge: ObservableObject {
    /// Accessibility (`kTCCServiceAccessibility`) — required to post the
    /// synthetic ⌘V into the foreground app.
    @Published private(set) var accessibilityGranted = true
    /// Input Monitoring (`kTCCServiceListenEvent`) — a SEPARATE permission,
    /// required for the global keyboard tap (the hotkey). Without it the
    /// hotkey only fires while Murmur is frontmost.
    @Published private(set) var inputMonitoringGranted = true

    var allPermissionsGranted: Bool {
        accessibilityGranted && inputMonitoringGranted
    }

    private let monitor = GlobalHotKeyMonitor()
    private var pending: Task<Void, Never>?
    private var attached = false

    func attach(to dictation: DictationCoordinator) {
        guard !attached else { return }
        attached = true
        monitor.onPress = { [weak self] in
            self?.enqueue { await dictation.toggle() }
        }
        monitor.onRelease = { [weak self] cancelled in
            self?.enqueue {
                if cancelled {
                    await dictation.cancel()
                } else {
                    await dictation.toggle()
                }
            }
        }
        // Two DISTINCT TCC permissions, prompted once here (launch is the
        // right user-initiated moment, not mid-transcription):
        //  - Input Monitoring → the global keyboard tap (hotkey). Without it
        //    a listen-only tap is silently frontmost-only.
        //  - Accessibility    → posting the synthetic ⌘V (auto-paste).
        // Both only take effect after an app relaunch (the UI says so).
        let imTrusted = GlobalHotKeyMonitor.inputMonitoringTrusted(prompt: true)
        let axTrusted = Self.accessibilityTrusted(prompt: true)
        let started = monitor.start()
        inputMonitoringGranted = imTrusted && started
        accessibilityGranted = axTrusted
    }

    /// Re-check after the user (says they) granted the permissions. The tap
    /// was likely created while untrusted, so tear it down and recreate —
    /// even then a TCC grant for an event tap usually only takes effect after
    /// an app relaunch, which the UI tells the user.
    func retry() {
        monitor.stop()
        let started = monitor.start()
        inputMonitoringGranted =
            GlobalHotKeyMonitor.inputMonitoringTrusted(prompt: false) && started
        accessibilityGranted = Self.accessibilityTrusted(prompt: false)
    }

    private static func accessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func enqueue(_ action: @escaping () async -> Void) {
        let previous = pending
        pending = Task {
            await previous?.value
            await action()
        }
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
    @StateObject private var hotkey = HotKeyBridge()

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

            Text("Hold Right ⌘ anywhere to dictate")
                .font(.footnote)
                .foregroundStyle(.secondary)

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
                            HotKeyBridge.openInputMonitoringSettings()
                        }
                        Button("Accessibility") {
                            HotKeyBridge.openAccessibilitySettings()
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
        }
        .padding(40)
        .frame(minWidth: 360, minHeight: 240)
        .onAppear { hotkey.attach(to: dictation) }
    }
}

#Preview {
    ContentView()
}
