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
    @StateObject private var recorder = AudioRecorder()

    var body: some View {
        VStack(spacing: 16) {
            Text("Murmur")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("v\(Murmur.version)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button(action: toggle) {
                Text(recorder.isRecording ? "Stop" : "Record")
                    .frame(minWidth: 120)
            }
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])

            if let url = recorder.lastSavedURL {
                Text("Saved: \(url.lastPathComponent)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let err = recorder.lastError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(minWidth: 360, minHeight: 240)
    }

    private func toggle() {
        Task {
            if recorder.isRecording {
                await recorder.stop()
            } else {
                await recorder.start()
            }
        }
    }
}

#Preview {
    ContentView()
}
