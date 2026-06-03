import Foundation

/// A proper-noun term murmur prefers when a transcript token is a near-miss for
/// it. Sourced from gbrain entities (build-time bake + runtime refresh) and
/// from user corrections captured by the one-tap loop (C).
///
/// Single Latin-script token by construction: the fuzzy matcher works
/// token-by-token, so multi-word names ("Sommet Labs") are split into their
/// distinctive tokens upstream (the export script and `CorrectionStore`).
public struct Term: Equatable, Sendable {
    /// The canonical spelling to emit (e.g. "gbrain", "Yei", "Sommet").
    public let canonical: String
    public init(_ canonical: String) { self.canonical = canonical }
}

/// A user-confirmed {heard → intended} correction captured by the one-tap loop
/// (C). `heard` is what the pipeline produced; `intended` is the right
/// spelling. Persisted to disk so the correction survives relaunch and
/// compounds across sessions.
public struct CorrectionPair: Equatable, Sendable, Codable {
    public let heard: String
    public let intended: String
    public init(heard: String, intended: String) {
        self.heard = heard
        self.intended = intended
    }
}

/// The combined correction source the matcher consumes.
///
/// - `directMappings` are exact, user-confirmed replacements (from C). Applied
///   first and unconditionally — no fuzzy threshold, no real-word guard.
/// - `terms` drive the fuzzy edit-distance pass over unknown tokens.
public struct CorrectionDictionary: Equatable, Sendable {
    public var terms: [Term]
    public var directMappings: [CorrectionPair]

    public init(terms: [Term] = [], directMappings: [CorrectionPair] = []) {
        self.terms = terms
        self.directMappings = directMappings
    }

    public static let empty = CorrectionDictionary()
}

/// The seam the coordinator corrects the raw transcript through (A'). A class
/// protocol so the coordinator can hold an optional reference while
/// `CorrectionStore` — a reference type owning mutable, persisted state — is
/// the concrete conformer the SwiftUI layer also drives the capture UI from.
@MainActor
public protocol TextCorrecting: AnyObject {
    func correct(_ text: String) -> String
}
