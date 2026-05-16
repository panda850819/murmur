import SwiftUI
import MurmurCore

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
    }
}

#Preview {
    ContentView()
}
