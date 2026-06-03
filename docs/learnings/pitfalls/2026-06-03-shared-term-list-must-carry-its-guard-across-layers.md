---
date: 2026-06-03
type: pitfall
tags: [architecture, single-source-of-truth, llm, prompt, proper-noun, guard, correction, dictation]
sprint: murmur-bprime-groq-glossary
---

# A list shared across a guarded deterministic layer and an LLM layer: the guard does NOT travel with the list

## What was built

B' reuses A's gbrain proper-noun term list as the glossary in the Groq enhance
prompt — "single source of truth", one list feeding both the on-device
deterministic corrector (A') and the cloud LLM (B').

## The trap (caught by the architecture review, not by the implementer)

A' pairs the list with a `isRealWord` guard: it refuses to re-case or fuzzy-match
a token the speaker used that is itself a real word, precisely because an
entity-sourced list inevitably contains generic words. The shipped `terms.json`
proves it: `Bob`, `Axis`, `Nous`, `midnight`, `Ose`, `Tuc`.

"Single source of truth" copied the LIST into B' but not the GUARD that makes the
list safe to apply. B' hands those same terms to the LLM as "known proper nouns,
use these exact spellings", which can coerce `midnight → Midnight` when the
speaker meant the time. The post-enhance A' pass does not reliably undo it (A'
canonical-cases on exact match, and may accept the capitalized form as a real
word). So the two layers shared a list but diverged in safety behavior.

## The lesson

When the SAME data crosses into a second layer with a different correction
mechanism, re-derive the safety invariant for that layer — don't assume "shared
list" means "shared behavior". The guard is a property of the (list + layer)
pair, not of the list. Either:
- port the guard (filter the LLM glossary through the same `isRealWord`), or
- give the layer its own analog guard, or
- consciously accept the gap and document it.

## Disposition (Panda, 2026-06-03: accept + document)

Do NOT filter the glossary by `isRealWord`: those real-word terms (Bob = a
person, Axis/Nous = companies) are usually the names the speaker MEANS, and
filtering would lose B's reinforcement of exactly them. The accepted B'-side
guard is soft: the enhance prompt's "use these … when the speech clearly refers
to one" hedge, plus the deterministic post-enhance A' pass. Residual risk is
low-frequency cosmetic mis-capitalization of a generic word used as itself.
Documented at `ProperNounCorrector.glossary` and `GroqClient.cleanupSystemPrompt`.

## How it was caught

The architecture lens of the multi-agent `/review` (the opus pass), which had the
context to compare A's guard against B's use of the same list. The cold reviewer
and Codex both missed it — it needed the cross-layer view, not a fresh-eyes diff
read. Distinct from the privacy pitfall ([[2026-06-03-llm-glossary-broadens-third-party-disclosure]]),
which was about disclosure; this is about correctness divergence.
