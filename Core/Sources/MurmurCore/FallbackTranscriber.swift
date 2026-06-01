import Foundation

/// Tries on-device transcription first; on throw, retries with a cloud engine.
/// Reuses the existing `Transcribing` seam, so the coordinator is unchanged —
/// it still sees one `Transcribing`.
///
/// Fallback fires only when the primary *throws* (model not downloaded, no
/// network for the model fetch, decode failure). An empty transcript (silence,
/// no speech) is a valid result, not a failure, and does NOT trigger the cloud
/// hop — that would upload silence and spend tokens for nothing.
public struct FallbackTranscriber: Transcribing {
    private let primary: any Transcribing
    private let fallback: any Transcribing

    public init(primary: any Transcribing, fallback: any Transcribing) {
        self.primary = primary
        self.fallback = fallback
    }

    public func transcribe(wavURL: URL) async throws -> String {
        do {
            return try await primary.transcribe(wavURL: wavURL)
        } catch {
            return try await fallback.transcribe(wavURL: wavURL)
        }
    }
}
