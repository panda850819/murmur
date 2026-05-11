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
    var body: some View {
        VStack(spacing: 12) {
            Text("Murmur")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("v\(Murmur.version) · WhisperKit: \(Murmur.whisperKitReachable())")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Sprint 2 scaffold. Real dictation arrives next.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(minWidth: 360, minHeight: 200)
    }
}

#Preview {
    ContentView()
}
