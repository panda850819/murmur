import Foundation
import MurmurCore

// MurmurEval — playback runner for BRIEF Quality gate #1.
//
// Reads an eval manifest, transcribes every clip through the SAME
// MurmurCore `Transcribing` path the app uses, scores WER/CER per clip,
// then either bootstraps a baseline or fails the build on regression vs
// an existing baseline. This binary does NOT synthesize audio — real
// Apple-device fixtures are recorded by Panda (docs/eval/RECORDING-KIT.md).

struct Args {
    var manifest = "docs/eval/fixtures/manifest.json"
    var baseline = "docs/eval/baseline.json"
    var model = "openai_whisper-base"
    var bootstrap = false
    var tolerance = 0.0
}

func parseArgs() -> Args {
    var a = Args()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        switch arg {
        case "--manifest": if let v = it.next() { a.manifest = v }
        case "--baseline": if let v = it.next() { a.baseline = v }
        case "--model": if let v = it.next() { a.model = v }
        case "--bootstrap-baseline": a.bootstrap = true
        case "--tolerance": if let v = it.next(), let d = Double(v) { a.tolerance = d }
        case "--help", "-h":
            print("""
            murmur-eval — WER/CER regression gate

              --manifest <path>     default docs/eval/fixtures/manifest.json
              --baseline <path>     default docs/eval/baseline.json
              --model <name>        WhisperKit model (default openai_whisper-base)
              --bootstrap-baseline  write baseline instead of comparing
              --tolerance <float>   allowed overall WER increase (default 0.0)
            """)
            exit(0)
        default:
            FileHandle.standardError.write(Data("unknown arg: \(arg)\n".utf8))
            exit(2)
        }
    }
    return a
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

let args = parseArgs()
let fm = FileManager.default
let manifestURL = URL(fileURLWithPath: args.manifest)

guard let manifestData = try? Data(contentsOf: manifestURL) else {
    fail("cannot read manifest: \(args.manifest)")
}
let manifest: EvalManifest
do {
    manifest = try JSONDecoder().decode(EvalManifest.self, from: manifestData)
} catch {
    fail("bad manifest json: \(error)")
}
guard !manifest.clips.isEmpty else {
    fail("manifest has no clips — record fixtures first (docs/eval/RECORDING-KIT.md)")
}

let fixturesDir = manifestURL.deletingLastPathComponent()
let transcriber: any Transcribing = WhisperKitTranscriber(modelName: args.model)

var entries: [EvalBaseline.Entry] = []
var totalDistance = 0
var totalRef = 0

for clip in manifest.clips {
    let wav = fixturesDir.appendingPathComponent(clip.file)
    guard fm.fileExists(atPath: wav.path) else {
        fail("missing clip file: \(wav.path)")
    }
    let hyp: String
    do {
        hyp = try await transcriber.transcribe(wavURL: wav)
    } catch {
        fail("transcribe failed for \(clip.id): \(error)")
    }
    let r = WER.score(
        reference: clip.reference,
        hypothesis: hyp,
        mode: clip.tokenization
    )
    entries.append(.init(id: clip.id, wer: r.rate, referenceCount: r.referenceCount))
    totalDistance += r.distance
    totalRef += r.referenceCount
    print(String(format: "  %@  WER=%.4f  (%d/%d)",
                 clip.id, r.rate, r.distance, r.referenceCount))
}

let overall = totalRef == 0 ? 0 : Double(totalDistance) / Double(totalRef)
print(String(format: "OVERALL WER=%.4f over %d clips", overall, manifest.clips.count))

let baselineURL = URL(fileURLWithPath: args.baseline)

if args.bootstrap {
    let b = EvalBaseline(
        model: args.model,
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        overallWER: overall,
        entries: entries
    )
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        try fm.createDirectory(
            at: baselineURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try enc.encode(b).write(to: baselineURL)
    } catch {
        fail("cannot write baseline: \(error)")
    }
    print("baseline written: \(args.baseline)")
    exit(0)
}

guard let prevData = try? Data(contentsOf: baselineURL),
      let prev = try? JSONDecoder().decode(EvalBaseline.self, from: prevData)
else {
    fail("no baseline at \(args.baseline) — run with --bootstrap-baseline first")
}
let delta = overall - prev.overallWER
if delta > args.tolerance {
    fail(String(format: "REGRESSION: WER %.4f > baseline %.4f (+%.4f, tol %.4f)",
                overall, prev.overallWER, delta, args.tolerance))
}
print(String(format: "OK: WER %.4f vs baseline %.4f (delta %+.4f)",
             overall, prev.overallWER, delta))
exit(0)
