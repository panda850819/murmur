import Foundation

/// A source of proper-noun terms for the corrector. Concrete sources read a
/// baked snapshot (build-time, source A) and/or a runtime-refreshed file
/// (source B) — the A+B hybrid sync.
///
/// A source that can't load returns `[]`; it never throws. A missing or
/// malformed file degrades to "no terms from here", never a crash.
public protocol TermSource {
    func load() -> [Term]
}

/// On-disk JSON shape shared by the baked snapshot and the runtime file:
/// `{ "version": 1, "terms": ["gbrain", "Yei", ...] }`. A plain string array —
/// each entry is one canonical Latin token.
struct TermFile: Codable {
    var version: Int
    var terms: [String]
}

/// Loads terms from a JSON file at `url`. `nil` url, missing/unreadable file, or
/// malformed JSON all yield `[]`.
public struct JSONTermSource: TermSource {
    private let url: URL?
    public init(url: URL?) { self.url = url }

    public func load() -> [Term] {
        guard
            let url,
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(TermFile.self, from: data)
        else { return [] }
        return file.terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(Term.init)
    }

    /// The baked snapshot shipped in the app bundle (build-time export, A).
    public static func bundled(
        resource: String = "terms",
        in bundle: Bundle = .main
    ) -> JSONTermSource {
        JSONTermSource(url: bundle.url(forResource: resource, withExtension: "json"))
    }
}

/// Unions several sources, first-seen-wins on case-insensitive canonical
/// collision. Put the fresher source first: the runtime file (B) precedes the
/// baked snapshot (A), so a refreshed spelling supersedes the bundled one while
/// terms present only in the snapshot still survive.
public struct CompositeTermSource: TermSource {
    private let sources: [TermSource]
    public init(_ sources: [TermSource]) { self.sources = sources }

    public func load() -> [Term] {
        var seen = Set<String>()
        var out: [Term] = []
        for source in sources {
            for term in source.load()
            where seen.insert(term.canonical.lowercased()).inserted {
                out.append(term)
            }
        }
        return out
    }
}
