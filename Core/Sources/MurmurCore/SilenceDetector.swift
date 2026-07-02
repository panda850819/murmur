import AVFoundation
import Foundation

/// Pre-transcribe guard for effectively-empty recordings (M5: "Audio is
/// silent" detect + retry). A muted mic, a wrong input device, or a grazed
/// hotkey produces a WAV full of (near-)zeros; running Whisper on it wastes
/// seconds and then pastes nothing useful. Detecting it up front lets the
/// coordinator fail fast with an actionable "try again".
///
/// Reads the file back through `AVAudioFile`, the mirror of how `WAVWriter`
/// wrote it (Float32 PCM, 16 kHz mono) — no hand-rolled RIFF parsing, and any
/// format `AVAudioFile` can decode works. Chunked reads keep the memory
/// footprint flat regardless of recording length (a 10-minute hold must not
/// materialize a 38 MB sample array just to compute one scalar).
public enum SilenceDetector {
    /// True ONLY when the recording at `wavURL` was fully decoded and is
    /// genuinely quiet: every frame read back and the RMS came in below
    /// `rmsThreshold`, or the file decoded cleanly to zero frames (an empty
    /// recording IS silence). Anything we could not verify — file won't open,
    /// buffer allocation fails, a mid-file read errors out — returns false:
    /// a false "silent" verdict here silently DROPS a real dictation (the
    /// coordinator bails before transcribing), whereas returning false just
    /// forwards the broken clip to the transcriber, which fails loudly with
    /// its own honest error. Losing speech is the worse failure, so the
    /// detector never claims silence it didn't measure.
    ///
    /// The default threshold 0.005 (≈ −46 dBFS) sits well below quiet speech
    /// (RMS ~0.02–0.1 at normal mic gain) but above electrical noise floor on
    /// a muted/disconnected input (~0.0001), so neither side false-trips.
    public static func isSilent(wavURL: URL, rmsThreshold: Float = 0.005) -> Bool {
        guard let file = try? AVAudioFile(forReading: wavURL) else {
            return false  // can't decode ⇒ can't claim silence; let Whisper report it
        }
        guard file.length > 0 else {
            return true  // fully decoded, zero samples: an empty recording IS silence
        }
        let format = file.processingFormat  // deinterleaved Float32
        let chunkFrames: AVAudioFrameCount = 4096  // matches WAVWriter's write chunk
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            return false
        }
        // Accumulate in Double: a long recording's sum of squares would lose
        // precision (and could even saturate comparisons) in Float32.
        var sumOfSquares = 0.0
        var sampleCount = 0
        while file.framePosition < file.length {
            guard (try? file.read(into: buffer, frameCount: chunkFrames)) != nil,
                  buffer.frameLength > 0,
                  let channels = buffer.floatChannelData
            else {
                // A mid-file read failure means the verdict would be computed
                // on a partial decode — that is not "fully decoded and quiet".
                return false
            }
            let frames = Int(buffer.frameLength)
            for channel in 0..<Int(format.channelCount) {
                let samples = channels[channel]
                for i in 0..<frames {
                    let s = Double(samples[i])
                    sumOfSquares += s * s
                }
            }
            sampleCount += frames * Int(format.channelCount)
        }
        guard sampleCount > 0 else { return false }  // nothing measured ⇒ no silence claim
        let rms = (sumOfSquares / Double(sampleCount)).squareRoot()
        return Float(rms) < rmsThreshold
    }
}
