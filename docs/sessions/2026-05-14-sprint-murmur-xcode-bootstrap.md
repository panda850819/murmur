---
date: 2026-05-14
type: sprint
state: SHIPPED
topic: murmur-xcode-bootstrap
mode: default
iteration: 1
persona: pandastack:eng-lead
tags: [sprint, shipped, xcode, infra, bootstrap]
---

# Sprint — murmur-xcode-bootstrap — 2026-05-14

Picks up from [`docs/sessions/2026-05-14-sprint-3-paused-xcode-infra.md`](2026-05-14-sprint-3-paused-xcode-infra.md) Path D (split infra fight out of Sprint 3).

## Capability probe

```
[1] AGENTS substrate    : ok
[2] vault root          : ok    (murmur has Inbox/ + docs/)
[3] lib/ files          : ok    (push-once, escape-hatch, skill-decision-tree, gate-contract)
[4] persona skills      : ok    (eng-lead — pure infra/build)
[5] cli tools           : ok    (swift 6.2.4, xcodebuild 26.3, xcodegen 2.45.4)
[6] write paths         : ok
```

## Stage progression

| Stage | Status | Output |
|---|---|---|
| 0 probe | ok | 6/6 green |
| 1 dojo | done | Critical finding: clean-state build already works — PAUSED2 "still failing" claim no longer reproduces |
| 2 grill (lite) | done | 3 Qs: scope (bottle the recipe) / IN-scope items (all 4) / reversibility (all 2-way) |
| 3 execute | done | 7 sub-steps: bootstrap.sh, verify, README, CI, learning, archive, mic static check |
| 4 review | done | 0 P0 / 0 P1 / 0 coverage / 0 drift; eng-lead Iron Laws all green |
| 5 ship gate | SHIPPED | review clean + user approved ship via PR |
| 6 terminal | done | commit `58abdec`, PR https://github.com/panda850819/murmur/pull/1 |

## Critical finding (dojo)

The PAUSED Sprint 3 checkpoint claimed `xcodebuild` could not reach
`WhisperKit` through the local SPM target. Re-tested from a clean state on
the same commit (`42511d6`): the chain works.

```
1. rm -rf Murmur.xcodeproj/
2. xcodegen generate
3. python3 scripts/patch-xcodeproj.py        ← patches 1 missing linkage
4. xcodebuild ... build                      → ** BUILD SUCCEEDED **
```

`MurmurCore` compiles with `import WhisperKit`. `WhisperKit.self` is
reachable.

The PAUSED2 mis-diagnosis traced to an `xcodebuild` invocation conflict:
`-arch arm64 -destination 'platform=macOS,arch=arm64' ARCHS=arm64` raises
*"destination implies architecture, architecture must not also be
specified"* — a harness error that masked the build's actual status.
Drop `-arch arm64` (keep `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`) and the chain
runs end-to-end.

→ Sprint scope shifted from "fight Xcode infra" to "bottle the existing
working flow so it stays working and is reproducible."

## What shipped

```
scripts/bootstrap.sh                                    new (+x)
docs/learnings/pitfalls/2026-05-14-xcodegen-local-      new
    package-product-dependency-missing-link.md
.github/workflows/ci.yml                                modified (added xcodebuild job)
README.md                                               modified (Build section rewrite)
docs/sessions/2026-05-14-sprint-3-paused-xcode-infra.md renamed from Inbox/ + Resolution appended
```

Commit: `58abdec` on branch `chore/xcode-bootstrap`. PR:
[#1](https://github.com/panda850819/murmur/pull/1).

## Verification trail (eng-lead "verify, don't assume")

| Check | Command | Result |
|---|---|---|
| Bootstrap idempotent + green | `rm -rf Murmur.xcodeproj && ./scripts/bootstrap.sh && xcodebuild ... build` | `BUILD SUCCEEDED` (run twice from clean) |
| Core tests | `cd Core && swift test` | 2/2 passed |
| `.app` bundle display name | `plutil -extract CFBundleDisplayName raw .../MurmurMac.app/Contents/Info.plist` | `Murmur` ✓ |
| Mic usage description set | same plutil | `Murmur uses your microphone...` ✓ |
| audio-input entitlement | `codesign -d --entitlements -` | `True` ✓ |
| app-sandbox entitlement | same | `True` ✓ |

End-to-end interactive mic-permission dialog test (BRIEF `goal-L0-f`)
deferred: the current app has no UI hook that calls
`AVCaptureDevice.requestAccess(for: .audio)`. Static prereqs for the dialog
are all in place; the trigger arrives in the next audio sprint.

## Gate log

| Stage | Gate decision |
|---|---|
| 2 grill | user picked "bottle the working recipe" + all 4 IN-scope items + "all two-way doors" |
| 4 review | clean (no auto-loop needed) |
| 5 ship | user picked "Ship — 走 /ship 流程 (commit + push + PR)" |

## OPEN_QUESTIONS

1. CI `xcodebuild` job on macos-15 — first run; surfaces any local↔CI
   Xcode/xcodegen version drift. Watch PR #1 checks; if it fails, the
   `brew install xcodegen` step's installed version + `xcodebuild`
   destination flags are the first suspects.
2. Mic-permission dialog interactive test — wait for Sprint 4 audio
   capture sprint to add the `AVCaptureDevice.requestAccess` call.
3. Remove `scripts/patch-xcodeproj.py` + the patch step in
   `scripts/bootstrap.sh` once XcodeGen ships the upstream fix and the
   project's local xcodegen is bumped (criteria in the learning note).

## Origin

- Carved off [`docs/sessions/2026-05-14-sprint-3-paused-xcode-infra.md`](2026-05-14-sprint-3-paused-xcode-infra.md) Path D
- Persona: `pandastack:eng-lead` (single-persona discipline — pure infra)
- Sprint protocol: `pandastack:sprint` default mode
