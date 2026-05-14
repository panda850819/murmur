---
date: 2026-05-14
type: pitfall
tags: [xcodegen, xcode, swift-package-manager, infra]
sprint: murmur-xcode-bootstrap
---

# XcodeGen 2.45.4: local Swift package product dependency missing `package = X` link

## Symptom

After `xcodegen generate` from a `project.yml` that references a **local**
Swift package via `packages: { Name: { path: SubDir } }`, the generated
`Murmur.xcodeproj/project.pbxproj` contains an `XCSwiftPackageProductDependency`
entry for the product, but the entry is missing the `package = <ref>;` line
that points back to the `XCLocalSwiftPackageReference` node.

`xcodebuild build` then fails to resolve the local module at compile time
even though `xcodebuild -resolvePackageDependencies` succeeds and the
package shows up in the resolved graph.

## Reproduction

```yaml
# project.yml (minimal)
packages:
  MurmurCore:
    path: Core
targets:
  App:
    dependencies:
      - package: MurmurCore
        product: MurmurCore
```

After `xcodegen generate` the pbxproj has:

```
/* MurmurCore */ = {
    isa = XCSwiftPackageProductDependency;
    productName = MurmurCore;   ← missing `package = <ref>` line above
};
```

A correctly-linked entry should look like:

```
/* MurmurCore */ = {
    isa = XCSwiftPackageProductDependency;
    package = <REF> /* XCLocalSwiftPackageReference "Core" */;
    productName = MurmurCore;
};
```

Remote packages (`url:` instead of `path:`) are written correctly. Only the
local-path case is affected.

## Root cause

XcodeGen 2.45.4 emits the local-package reference node and the product
dependency node, but the cross-link between them is dropped for local
packages. Confirmed by inspecting the generated pbxproj — the
`XCLocalSwiftPackageReference` exists with a stable id, but no
`XCSwiftPackageProductDependency` entry references that id.

## Workaround

`scripts/patch-xcodeproj.py` post-processes the generated pbxproj:

1. Discovers all `XCLocalSwiftPackageReference` entries: `{ name → ref_id }`.
2. For each local package, parses its `Package.swift` for `.library(name: "...")`
   product names.
3. Patches each matching `XCSwiftPackageProductDependency` to inject the
   missing `package = <ref_id> /* XCLocalSwiftPackageReference "..." */;` line.

Idempotent — re-running on already-patched pbxproj is a no-op.

Wrapped by `scripts/bootstrap.sh` so the regenerate flow is one command:

```bash
./scripts/bootstrap.sh   # xcodegen generate + patch-xcodeproj.py
```

## Removal trigger

Drop both `scripts/patch-xcodeproj.py` and the patch step in
`scripts/bootstrap.sh` when:

- XcodeGen ships a release that emits the `package = <ref>` link for
  local-path product dependencies, AND
- Murmur's local `xcodegen --version` is bumped to that release.

Verify by deleting `Murmur.xcodeproj/`, running `xcodegen generate` (no patch),
and grepping for `package = ` lines inside `XCSwiftPackageProductDependency`
blocks. If all local-package product entries have the link, the upstream fix
is in and the patch can go.

## Why not just hand-craft .xcodeproj

The murmur repo deliberately keeps `Murmur.xcodeproj/` gitignored — every
clone regenerates it from `project.yml`. Hand-crafted pbxproj files invite
Xcode auto-edit noise on every UI interaction (added file, scheme change,
build setting tweak) which then either gets committed by accident or causes
diff churn. `project.yml` is the source of truth; the patch script is the
plaster over a known XcodeGen bug.

## Origin

- First hit: Sprint 3 PAUSED1 / PAUSED2, 2026-05-14 (originally diagnosed as
  a 4-strike unfixable infra wall; the diagnosis itself was the bug — the
  patch already worked, but `xcodebuild` invocation flags
  (`-arch arm64 -destination ... arch=arm64`) raised a different
  "destination implies architecture" error that masked the underlying
  success).
- Patch script written + verified: same day in this sprint
  (murmur-xcode-bootstrap, 2026-05-14).
- Pattern: when a build-graph error keeps reappearing after multiple fixes,
  also re-test the invocation harness — the harness can hide the actual
  build result.
