---
schema_version: 1
date: 2026-06-04
type: pitfall
tags: [murmur, privacy, correction, filter, review, invariant]
---

# A downstream privacy filter built parallel to an upstream guard must be *provably* no looser than it — or it leaks

## Context

B' sends murmur's proper-noun glossary to Groq's enhance call. The
`GlossaryRelevanceFilter` (a new pre-M6 privacy gate) decides which glossary terms
are "relevant" to the utterance using fuzzy matching, layered alongside A'
(`ProperNounCorrector`), which already does on-device fuzzy correction with a full
guard set: direct-map, `isRealWord` input guard, `minFuzzyLength` token floor,
length-scaled `editThreshold` keyed off the TOKEN, and a `|Δlen|` prune.

## The trap

The filter was written by **re-porting some of A's guards from scratch** instead of
mirroring all of them. Each missing guard was a privacy leak, and the adversarial
review found them one per iteration:

1. **No real-word guard** → ordinary English words within the fuzzy radius of a
   stored name forwarded that private name to the cloud (`brain`→`gbrain`,
   `summer`→`Sommet`) even when no entity was spoken.
2. **Threshold keyed off TERM length only** (A' keys off token length) → a short
   non-word token leaked a longer term (`ye`→`Yei`) that A' itself would never act
   on (its `minFuzzyLength`/token-length floor blocks it).

Both are the **same shape**: the filter was strictly *more permissive* than the
guard it sits beside. Hand-porting guards piecemeal guarantees you eventually miss
one, and "the filter looks like A'" is not the same as "the filter ≤ A'".

## The fix / principle

Make the permissiveness relationship an **invariant you can state and check**, not a
side effect of copying code:

- Tolerance clamped to `editThreshold(min(token.count, term.count))`. Since
  `min ≤ token.count`, the clamped tolerance ≤ A's token-keyed tolerance, so any
  token the filter fuzzy-matches, A' would also have matched. The filter is
  uniformly ≤ A'. State that proof in the doc comment.
- Reuse the upstream guard *object*, not a reimplementation: `isRealWord` is now
  exposed on `TextCorrecting` and threaded from the bound corrector, so A' and the
  filter share one notion of "real word" by construction.
- Lock both halves with tests: privacy (a non-entity utterance ships zero terms)
  AND recall (a real-word entity spoken exactly is still kept — the exact-match arm
  must precede the guard). Mutation-test that the privacy tests fail when the guard
  is removed, so the suite is provably load-bearing, not vacuous.

## Smell

A second pass that re-derives a sibling pass's matching logic. If pass B sits beside
a battle-tested pass A and must not exceed A's reach, delegate to A's predicates or
prove `B ≤ A` arithmetically. Do not re-port A's guard set guard-by-guard and hope
you got them all — you won't, and for a privacy gate each miss is a disclosure.
