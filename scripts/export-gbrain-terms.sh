#!/usr/bin/env bash
# Export Panda's gbrain proper nouns to a term list murmur's on-device corrector
# (A') consumes. Single source of truth: the names ARE gbrain entities, so the
# dictionary is sourced, not hand-maintained.
#
# A+B HYBRID — this one script feeds both halves of the sync:
#   A (build-time bake): default output is the app-bundle resource, refreshed on
#     every dogfood rebuild (wired into scripts/bootstrap.sh).
#   B (runtime refresh):  point it at the Application Support file, e.g. from a
#     15-min launchd job, so terms update WITHOUT rebuilding murmur:
#       export-gbrain-terms.sh "$HOME/Library/Application Support/Murmur/gbrain-terms.json"
#     murmur reads that file at launch and it overrides the baked snapshot.
#
# Output schema: { "version": 1, "terms": ["gbrain", "Murmur", ...] }  (Latin tokens)
#
# Scope: companies + projects (coined-noun-dense) plus a seed of personal
# private nouns. People are OPT-IN (MURMUR_TERMS_INCLUDE_PEOPLE=1) — most are
# real-world names Whisper already handles, and including 249 first names would
# bloat the fuzzy term list with over-correction risk. C grows the list live for
# anything missed.
#
# CI-safe: if `gbrain` is not on PATH (CI, fresh clone), keep the existing
# generated terms.json. If it does not exist, seed it from the committed sample
# — never ship an empty bake.

set -euo pipefail

cd "$(dirname "$0")/.."

OUT="${1:-Sources/MurmurMac/Resources/terms.json}"
INCLUDE_PEOPLE="${MURMUR_TERMS_INCLUDE_PEOPLE:-0}"
SAMPLE="Sources/MurmurMac/Resources/terms.sample.json"

ensure_fallback_terms() {
    if [ -f "$OUT" ]; then
        return 0
    fi
    mkdir -p "$(dirname "$OUT")"
    cp "$SAMPLE" "$OUT"
    echo "seeded fallback terms from $SAMPLE -> $OUT"
}

if ! command -v gbrain >/dev/null 2>&1; then
    echo "gbrain not found; keeping existing $OUT (CI / no-brain environment)"
    ensure_fallback_terms
    exit 0
fi

# Base seed nouns that Whisper mis-hears. Private additions (entity/people
# names) live in scripts/seed-terms.local (gitignored, whitespace-separated)
# so they never sit in this committed file.
SEED="gbrain Murmur"
SEED_LOCAL="scripts/seed-terms.local"
if [ -f "$SEED_LOCAL" ]; then
    SEED="$SEED $(tr '\n' ' ' < "$SEED_LOCAL")"
fi

types="company project"
[ "$INCLUDE_PEOPLE" = "1" ] && types="$types person"

gbrain_raw="$(mktemp)"
raw="$(mktemp)"
trap 'rm -f "$gbrain_raw" "$raw"' EXIT

# Collect gbrain tokens SEPARATELY so an empty/errored result is
# distinguishable from a healthy one (the seed alone must not overwrite a good
# committed snapshot). Strip parenthetical segments — "(@handle)", "(NYSE:TSM)"
# — before tokenizing so handles/tickers don't leak in as terms.
#
# `|| true`: grep exits 1 on NO MATCH (gbrain unreachable, empty result, or
# all-CJK display names). Without it, `set -euo pipefail` would abort the whole
# script — and the bootstrap/dogfood build that calls it — on a transient blip.
for t in $types; do
    # gbrain list emits TSV: slug \t type \t date \t display-name
    gbrain list --type "$t" --limit 1000 2>/dev/null | cut -f4
done | sed -E 's/\([^)]*\)//g; s/（[^）]*）//g' | grep -oE '[A-Za-z][A-Za-z]+' > "$gbrain_raw" || true

if [ ! -s "$gbrain_raw" ]; then
    echo "gbrain returned no terms (DB down / empty result?); keeping existing $OUT"
    ensure_fallback_terms
    exit 0
fi

# Healthy result: merge the personal-noun seed with the gbrain tokens.
{ for w in $SEED; do echo "$w"; done; cat "$gbrain_raw"; } > "$raw"

python3 - "$raw" "$OUT" <<'PY'
import json, os, sys
src, out = sys.argv[1], sys.argv[2]

# Generic legal / ticker / org / common-word tokens that aren't useful proper
# nouns and would only add fuzzy-target noise. The runtime real-word guard
# protects real-word INPUTS, but the fuzzy TARGET list is unfiltered, so a
# non-word slip could be pulled toward a common-word term — keep them out here.
STOP = {
    "inc", "ltd", "llc", "co", "corp", "corporation", "group", "holdings",
    "capital", "partners", "ventures", "fund", "labs", "lab", "the", "and",
    "for", "adr", "nyse", "nasdaq", "blk", "stt", "tsm", "kyb", "review",
    "deployment", "monitor", "brain", "media", "electric", "industries",
    "manufacturing", "semiconductor", "fintech", "protocol", "research",
    "audit", "eats", "private", "international",
    # common English words that leaked through maximal-Latin-run splitting
    "finance", "street", "state", "pro", "night", "skills", "apple", "google",
    "uber", "taiwan", "beast", "confident", "robotics", "voyage", "combinator",
}

seen, terms = set(), []
for line in open(src, encoding="utf-8"):
    w = line.strip()
    if len(w) < 3:            # skip 1-2 char tokens (too ambiguous to fuzzy-match)
        continue
    k = w.lower()
    if k in STOP or k in seen:  # drop noise; case-insensitive dedupe, keep first casing
        continue
    seen.add(k)
    terms.append(w)
terms.sort(key=str.lower)
os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
with open(out, "w", encoding="utf-8") as f:
    json.dump({"version": 1, "terms": terms}, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"wrote {len(terms)} terms -> {out}")
PY
