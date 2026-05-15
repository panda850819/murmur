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
    @StateObject private var transcriber = Transcriber.makeDefault()

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
            .disabled(transcriber.isTranscribing)

            if transcriber.isTranscribing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Transcribing…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let text = transcriber.transcript {
                ScrollView {
                    Text(text.isEmpty ? "(no speech detected)" : text)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 160)
            }
            if let url = recorder.lastSavedURL {
                Text("Saved: \(url.lastPathComponent)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let err = recorder.lastError ?? transcriber.lastError {
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
                let previousURL = recorder.lastSavedURL
                await recorder.stop()
                if let url = recorder.lastSavedURL,
                   url != previousURL,
                   recorder.lastError == nil {
                    await transcriber.transcribe(wavURL: url)
                }
            } else {
                await recorder.start()
            }
        }
    }
}

#Preview {
    ContentView()
}
