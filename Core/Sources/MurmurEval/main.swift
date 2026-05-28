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
    var allowModelChange = false
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
        case "--allow-model-change": a.allowModelChange = true
        case "--help", "-h":
            print("""
            murmur-eval — WER/CER regression gate

              --manifest <path>     default docs/eval/fixtures/manifest.json
              --baseline <path>     default docs/eval/baseline.json
              --model <name>        WhisperKit model (default openai_whisper-base)
              --bootstrap-baseline  write baseline instead of comparing
              --tolerance <float>   allowed overall WER increase (default 0.0)
              --allow-model-change  compare even if baseline model differs
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
// A clip with an empty reference scores rate 1.0 but contributes 0 to
// totalRef, silently inflating the token-weighted overall WER. Every
// fixture must carry verbatim ground truth.
for clip in manifest.clips where clip.reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    fail("clip '\(clip.id)' has an empty reference — every fixture needs verbatim ground truth")
}

let fixturesDir = manifestURL.deletingLastPathComponent()
let transcriber: any Transcribing = WhisperKitTranscriber(modelName: args.model)

var entries: [EvalBaseline.Entry] = []
var totalDistance = 0
var totalRef = 0
// Per-group running sums keyed by id prefix (drop the trailing -NN), so
// the Bug #1 zone (zh-short) stays visible instead of being diluted in
// the token-weighted overall — short zh is a small share of total chars.
var groupDistance: [String: Int] = [:]
var groupRef: [String: Int] = [:]

func groupKey(_ id: String) -> String {
    let parts = id.split(separator: "-")
    return parts.count > 1 ? parts.dropLast().joined(separator: "-") : id
}

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
    let g = groupKey(clip.id)
    groupDistance[g, default: 0] += r.distance
    groupRef[g, default: 0] += r.referenceCount
    print(String(format: "  %@  WER=%.4f  (%d/%d)",
                 clip.id, r.rate, r.distance, r.referenceCount))
}

let overall = totalRef == 0 ? 0 : Double(totalDistance) / Double(totalRef)
print(String(format: "OVERALL WER=%.4f over %d clips", overall, manifest.clips.count))
for g in groupDistance.keys.sorted() {
    let gd = groupDistance[g]!, gr = groupRef[g]!
    let rate = gr == 0 ? 0 : Double(gd) / Double(gr)
    print(String(format: "  [%@]  WER=%.4f  (%d/%d)", g, rate, gd, gr))
}

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

// Distinguish "no baseline yet" from "baseline exists but is corrupt".
// Collapsing them tempts a user into re-bootstrapping over a real
// baseline they meant to compare against (a ghost-baseline mistake).
guard fm.fileExists(atPath: baselineURL.path) else {
    fail("no baseline at \(args.baseline) — run with --bootstrap-baseline first")
}
let prev: EvalBaseline
do {
    prev = try JSONDecoder().decode(EvalBaseline.self, from: Data(contentsOf: baselineURL))
} catch {
    fail("baseline at \(args.baseline) is unreadable or corrupt (\(error)) — fix the file or re-bootstrap deliberately")
}

// The comparison is only meaningful if the baseline was bootstrapped on
// the same model and the same clip set. Otherwise the gate passes/fails
// on an apples-to-oranges delta.
if prev.model != args.model && !args.allowModelChange {
    fail("baseline model '\(prev.model)' != run model '\(args.model)' — re-bootstrap or pass --allow-model-change")
}
let prevIDs = Set(prev.entries.map(\.id))
let currIDs = Set(entries.map(\.id))
if prevIDs != currIDs {
    let added = currIDs.subtracting(prevIDs).sorted()
    let removed = prevIDs.subtracting(currIDs).sorted()
    fail("manifest clip set differs from baseline (added: \(added), removed: \(removed)) — re-bootstrap")
}
let prevRefCount = Dictionary(uniqueKeysWithValues: prev.entries.map { ($0.id, $0.referenceCount) })
for e in entries where prevRefCount[e.id] != e.referenceCount {
    fail("clip '\(e.id)' reference length changed (baseline \(prevRefCount[e.id] ?? -1), now \(e.referenceCount)) — reference was edited; re-bootstrap")
}

let delta = overall - prev.overallWER
if delta > args.tolerance {
    fail(String(format: "REGRESSION: WER %.4f > baseline %.4f (+%.4f, tol %.4f)",
                overall, prev.overallWER, delta, args.tolerance))
}
print(String(format: "OK: WER %.4f vs baseline %.4f (delta %+.4f)",
             overall, prev.overallWER, delta))
exit(0)
