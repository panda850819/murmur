import Foundation

/// One completed dictation as it landed in the document (M5 history). `text`
/// is the PASTED output (post-enhance / translated / answered), not the raw
/// Whisper transcript — history mirrors what the user actually got. `mode` is
/// a plain string ("dictate" / "translate" / "ask") rather than the
/// `DictationMode` enum so a record decoded by a future build with renamed /
/// added cases never fails to load.
public struct DictationRecord: Codable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let mode: String
    public let text: String
    public let wordCount: Int

    public init(id: UUID = UUID(), date: Date = Date(), mode: String, text: String, wordCount: Int) {
        self.id = id
        self.date = date
        self.mode = mode
        self.text = text
        self.wordCount = wordCount
    }
}

/// Owns the local dictation history (M5): a capped, newest-first list of
/// `DictationRecord`s persisted as JSON. Local only — nothing here ever
/// crosses the network; the privacy story is "your transcripts stay on disk
/// in your own Application Support".
///
/// Mirrors `CorrectionStore`'s shape on purpose: `@MainActor ObservableObject`
/// with an injectable `storeURL` (nil ⇒ in-memory only, the test wiring) and
/// best-effort write-through persistence — an unwritable disk must never
/// crash or block a dictation.
@MainActor
public final class HistoryStore: ObservableObject {
    /// Hard cap so the JSON file (and the SwiftUI list backing it) can't grow
    /// unboundedly under heavy daily use. 200 ≈ a few weeks of dictations;
    /// oldest drop off first.
    public static let capacity = 200

    /// Stored records, newest first (index 0 = most recent dictation).
    @Published public private(set) var records: [DictationRecord]

    private let storeURL: URL?

    public init(storeURL: URL?) {
        self.storeURL = storeURL
        self.records = Self.loadRecords(from: storeURL)
    }

    /// Record a completed dictation. Newest-first insert, capped at
    /// `capacity` (oldest dropped), then write-through to disk.
    public func append(mode: DictationMode, text: String) {
        let record = DictationRecord(
            mode: Self.label(for: mode),
            text: text,
            wordCount: Self.wordCount(of: text)
        )
        records.insert(record, at: 0)
        if records.count > Self.capacity {
            records.removeLast(records.count - Self.capacity)
        }
        persist()
    }

    /// Wipe the history (UI "Clear" button). Persists the empty list so the
    /// wipe survives relaunch.
    public func clear() {
        records = []
        persist()
    }

    // MARK: - Stats (M5, derived — no separate counters to drift)

    /// Aggregates derived live from `records`, so they can never disagree
    /// with the visible history. `estMinutesSaved` = time the words would
    /// have taken to type (40 wpm) minus the time they took to speak
    /// (150 wpm), floored at 0.
    public var stats: (dictations: Int, words: Int, estMinutesSaved: Double) {
        let words = records.reduce(0) { $0 + $1.wordCount }
        return (records.count, words, Self.estMinutesSaved(words: words))
    }

    /// Pure stats math, split out for direct unit testing. 40 wpm typing vs
    /// 150 wpm speaking are the rough averages the "time saved" pitch uses
    /// everywhere (Typeless included); this is an estimate, not telemetry.
    nonisolated public static func estMinutesSaved(words: Int) -> Double {
        let typingMinutes = Double(words) / 40.0
        let speakingMinutes = Double(words) / 150.0
        return max(0, typingMinutes - speakingMinutes)
    }

    // MARK: - Word counting

    /// Word count that survives murmur's primary use case, code-mixed
    /// CJK + English dictation. Plain whitespace splitting undercounts CJK
    /// badly ("今天開會" would be 1 "word"), so: each CJK character counts as
    /// one word, and each whitespace-separated run of non-CJK characters
    /// counts as one word. "今天 deploy gbrain 到 prod" ⇒ 2 + 3 + 1 = 6.
    nonisolated public static func wordCount(of text: String) -> Int {
        var count = 0
        var inToken = false
        for ch in text {
            if isCJK(ch) {
                // A CJK char also terminates any Latin token it abuts
                // ("用gbrain開會" ⇒ 用 + gbrain + 開 + 會 = 4).
                if inToken {
                    count += 1
                    inToken = false
                }
                count += 1
            } else if ch.isWhitespace || ch.isNewline {
                if inToken {
                    count += 1
                    inToken = false
                }
            } else {
                inToken = true
            }
        }
        if inToken { count += 1 }
        return count
    }

    /// Han (incl. Extension A + compatibility), Hiragana, Katakana, and
    /// precomposed Hangul ranges — the scripts where "one character ≈ one
    /// word" holds. Checked on the first scalar; murmur's transcripts are
    /// NFC text where that is the character's identity.
    nonisolated private static func isCJK(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3400...0x4DBF,    // CJK Extension A
             0x4E00...0x9FFF,    // CJK Unified Ideographs
             0xF900...0xFAFF,    // CJK Compatibility Ideographs
             0x3040...0x309F,    // Hiragana
             0x30A0...0x30FF,    // Katakana
             0xAC00...0xD7AF:    // Hangul Syllables
            return true
        default:
            return false
        }
    }

    // MARK: - Mode labels

    /// Stable string form of `DictationMode` for persistence (see
    /// `DictationRecord.mode` doc) and the UI's mode tag.
    nonisolated static func label(for mode: DictationMode) -> String {
        switch mode {
        case .dictate: return "dictate"
        case .translate: return "translate"
        case .ask: return "ask"
        }
    }

    // MARK: - Persistence (mirrors CorrectionStore)

    private static func loadRecords(from url: URL?) -> [DictationRecord] {
        guard
            let url,
            let data = try? Data(contentsOf: url),
            let records = try? JSONDecoder().decode([DictationRecord].self, from: data)
        else { return [] }
        return records
    }

    private func persist() {
        guard let storeURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(records)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            // Persistence is best-effort: an unwritable history must not
            // crash dictation. The in-memory list still serves this session.
        }
    }
}

public extension HistoryStore {
    /// Default wiring: `history.json` next to `corrections.json` under the
    /// app's Application Support — same directory resolution as
    /// `CorrectionStore.makeDefault()` so all murmur state lives in one place.
    static func makeDefault() -> HistoryStore {
        let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("Murmur", isDirectory: true)

        return HistoryStore(storeURL: support?.appendingPathComponent("history.json"))
    }
}
