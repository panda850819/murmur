---
date: 2026-06-03
type: pitfall
tags: [privacy, groq, llm, prompt, glossary, third-party-disclosure, dictation, gbrain]
sprint: murmur-bprime-groq-glossary
---

# Reusing an on-device "single source of truth" list as LLM prompt context silently broadens third-party disclosure

## What was tried

B' injects murmur's proper-noun glossary (the same gbrain-sourced term list A'
uses on-device) into the Groq enhance system prompt, so the cloud cleanup pass
has the vocabulary for segmentation + code-mix. The "single source of truth"
framing felt clean: A' and B' draw from one list, no drift.

## The trap

"Single source of truth" reasoned about *correctness*, not *disclosure*. The
on-device list was harmless on-device. The moment it becomes ambient prompt
context, every enhance call ships the **whole** list to a third party (Groq) —
including entities the user never spoke in that utterance (holdings, people,
private projects). Dictating "hello world" with no proper noun still transmits
the full private roster.

This is a *different* privacy surface from the one already tracked:

| | terms.json-at-rest (prior gate) | B' glossary over-the-wire (this) |
|---|---|---|
| Recipient | anyone with the .app / repo | Groq (third party) |
| Trigger | possessing the artifact | every cloud enhance call |
| Threat | local disclosure | network disclosure of unspoken entities |

The brief had tracked glossary relevance-filtering, but framed it purely as a
*prompt-size* concern with a "once the list is large" trigger. The privacy
dimension was unowned by both the brief and the ROADMAP (ROADMAP §3 said only
the *transcript* goes to Groq).

## The lesson

When a list/context object crosses a trust boundary it didn't cross before
(on-device → cloud prompt), re-evaluate disclosure independently of correctness.
A "shared source of truth" that was fine in one layer can be a leak in another.
The same mitigation can serve multiple axes: utterance-relevance filtering (only
inject terms fuzzy-near the actual transcript) collapses the privacy surface to
"names you actually said", AND bounds prompt size, AND shrinks LLM
hallucinated-name risk — one fix, three findings.

## Disposition

Accepted for personal dogfood (Groq enhance is opt-in via `GROQ_API_KEY`; Groq
already receives the spoken transcript; fully reversible). Registered as a
**pre-M6 / pre-TestFlight hard gate** in ROADMAP §3 + M6 rows, alongside the
terms.json-at-rest gate. The relevance filter is the named fix.

## How it was caught

Adversarial multi-agent review (prompt-safety/privacy dimension) on the B' diff,
then an independent skeptic pass that verified every load-bearing claim against
the diff + terms.json content before confirming. The implementing pass had
flagged the surface itself but under-weighted it; the dedicated privacy lens
sized it correctly as a distinct, in-scope-for-B' P1.
