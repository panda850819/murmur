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

            if dictation.canEnhance {
                Toggle("Clean up with AI", isOn: $dictation.enhanceEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
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
