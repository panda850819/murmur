---
date: 2026-05-16
type: pitfall
topic: macOS CGEvent keyboard tap needs Input Monitoring, NOT Accessibility
tags: [pitfall, macos, tcc, cgevent, permissions, murmur]
sprint: murmur-sprint-5-hotkey-paste
---

# macOS: a global keyboard CGEvent tap needs **Input Monitoring**, not Accessibility

## Symptom

A `CGEvent.tapCreate(tap: .cgSessionEventTap, options: .listenOnly, …)`
listening for `flagsChanged` / `keyDown` "works" — but **only while your own
app is frontmost**. Switch to any other app and the global hotkey goes dead.
No error, no nil from `tapCreate`, no crash. `AXIsProcessTrusted()` can even
return `true` (Accessibility granted) and the tap is *still* frontmost-only.

## Root cause

macOS Catalina (10.15+) split keyboard-event observation out of
Accessibility into a **separate TCC permission: Input Monitoring**
(`kTCCServiceListenEvent`). The two are independent:

| Action | TCC permission | API to check |
|---|---|---|
| Observe global keyboard input (a listen-only key tap) | **Input Monitoring** | `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` |
| Post synthetic events into another app (e.g. ⌘V) | **Accessibility** | `AXIsProcessTrusted()` |
| Record mic audio | Microphone | TCC mic prompt (Info.plist usage string) |

Without Input Monitoring, `CGEvent.tapCreate` for keyboard events **still
returns a valid tap** — it is silently scoped to the creating process's own
events only. So "tapCreate succeeded" is necessary but **not sufficient**;
it is not a permission signal at all.

A dictation app that types into other apps needs **both** Input Monitoring
(to hear the hotkey) **and** Accessibility (to paste) — plus Microphone.
Three distinct prompts. Granting only Accessibility (the intuitive one for
"control other apps") leaves the hotkey frontmost-only.

## Fix

Gate the hotkey on the real signal and prompt for it explicitly:

```swift
import IOKit.hid

static func inputMonitoringTrusted(prompt: Bool) -> Bool {
    let granted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        == kIOHIDAccessTypeGranted
    if !granted, prompt { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
    return granted
}
```

Track Input Monitoring and Accessibility as **separate** user-facing states;
surface a checklist of which is missing. Both grants only take effect after
an **app relaunch** — recreating the tap in-process is not enough; tell the
user to quit and reopen.

Deep links to the two panes:
- `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`
- `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`

## Why this is non-obvious (cost: 3 smoke iterations)

1. `tapCreate` returning non-nil reads like success — there is no failure
   signal for the missing permission.
2. The frontmost-only behaviour looks like a run-loop / focus bug, not a
   permission bug — it sends you debugging the wrong layer.
3. "Control other apps → Accessibility" is the intuitive mental model, and
   granting *only* Accessibility makes the *paste* half work, which masks
   the missing Input Monitoring with partial success.
4. Ad-hoc-signed dev builds change cdhash every `xcodebuild`, so the TCC
   grant evaporates each rebuild — easy to misread as "the fix didn't work"
   when really the permission was just re-revoked. Dogfood from a stable
   copied `.app`, regrant only on real rebuild.

## Origin

- Murmur Sprint 5 (`murmur-sprint-5-hotkey-paste`, 2026-05-16). Smoke 1:
  false-positive `accessibilityGranted` (sourced from `tapCreate` bool) →
  no permission UI shown at all. Smoke 2: AX-detection fixed (gated on
  `AXIsProcessTrusted()`), warning/paste-error correct — but hotkey still
  frontmost-only. Smoke 3: added Input Monitoring (`IOHIDCheckAccess`)
  detection + prompt → cross-app hotkey + auto-paste validated by user.
- Pattern: each fix was correct and changed the symptom, which is how you
  know it is progressive TCC-layer discovery, not a patch-and-pray spiral.
