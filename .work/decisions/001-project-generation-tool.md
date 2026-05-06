# Decision 001: Project Generation Tool

**Status**: APPROVED 2026-05-06
**Date**: 2026-05-06
**Milestone**: M1, Phase 0

## Context

CLAUDE.md mandates "ZERO third-party Swift packages. No CocoaPods, no Carthage, no SPM dependencies beyond Apple frameworks." The constraint targets runtime/build-product dependencies that ship inside the app binary.

To execute M1, an `.xcodeproj` must be created with iOS app target, watchOS app target, and a unit test target, plus entitlements, Info.plists, and proper scheme configuration.

There is no Apple-supplied CLI to author a new `.xcodeproj`. Apple's only sanctioned path is opening Xcode.app and clicking through File > New > Project, then manually adding the watchOS target and the test target. That is incompatible with autonomous milestone execution by Claude Code.

## Options Considered

### Option A: `xcodegen` (Homebrew-installed Swift tool)

- Installed via `brew install xcodegen`. Not bundled in the app.
- Reads a `project.yml` source-of-truth file, emits a fully-formed `.xcodeproj`.
- Lightweight (single binary), actively maintained (yonaskolb/XcodeGen), large adoption in iOS ecosystem.
- The `project.yml` is committed to the repo. The `.xcodeproj` can be regenerated at any time.
- Output is plain Apple-format `.xcodeproj`. Once generated, Xcode treats it identically to a hand-authored project.

### Option B: `Tuist` (Homebrew-installed Swift tool)

- Heavier: Swift DSL files (`Project.swift`, `Workspace.swift`), introduces Tuist-specific concepts (cache, graph, signing dance), more moving parts.
- More feature-rich than necessary for this project.
- Adds developer-side complexity for marginal benefit at this scale.

### Option C: Hand-author the `.xcodeproj` PBXProj file

- The `.xcodeproj/project.pbxproj` is a structured plist with stable UUIDs.
- For 2 app targets + 1 test target plus entitlements, it is roughly 2k-4k lines.
- Hand-authoring is error-prone and creates maintenance pain on every target/file change.
- Rejected: high risk of subtle build failures discovered late.

### Option D: Open Xcode interactively, user does the clicks

- Defeats the autonomy goal of CLAUDE.md "Execute M1 task by task."
- User would need to repeat the procedure for any structural change (new target in M6 widgets, M2 Live Activity).
- Rejected: human bottleneck on every milestone with new targets.

### Option E: Use SPM (`Package.swift`) to build the app

- SPM supports `executableTarget` and limited app-style products on macOS, but iOS app + watchOS app + WidgetKit + ActivityKit extensions are not first-class SPM products.
- Rejected: SPM does not currently support the target types this project needs.

## Decision

**Adopt Option A (xcodegen) as a build-time developer tool only.**

Rationale:

1. xcodegen is not a third-party Swift package shipped in the app binary. Output is plain Apple-format Xcode project. CLAUDE.md's "ZERO third-party Swift packages" intent is preserved.
2. `project.yml` becomes the human-readable source of truth, committed to git. The `.xcodeproj` is also committed (for IDE convenience and to preserve scheme details), but can be regenerated deterministically from `project.yml`.
3. Lower complexity than Tuist; well-established pattern.
4. Supports App Group and iCloud entitlements declaratively.
5. Supports per-target deployment versions (iOS 18.0 for iOS app, watchOS 11.0 for watch app).
6. Supports adding the future M2 Live Activity extension, M6 widgets extension cleanly.

## Impact

### What changes

- Add `brew install xcodegen` to README's prerequisite list.
- Commit `project.yml` at repo root.
- Run `xcodegen generate` to create `PersonalOptimization.xcodeproj`. Commit the generated project.
- For any future structural change (new target, new file outside an existing group), update `project.yml` and re-run `xcodegen generate`.

### What does not change

- App binary contents: zero xcodegen code in the shipped app.
- App bundle size: zero impact.
- Build pipeline at runtime: `xcodebuild` operates on the generated `.xcodeproj` exactly as if it were hand-authored.
- Privacy manifest: no new entries needed.

### Trade-offs accepted

- One additional Homebrew tool on the developer machine.
- A small `project.yml` file becomes the structural source of truth, slightly different from the typical "Xcode IDE is the source of truth" workflow.

## Alternatives if user rejects

If the user declines xcodegen:

- **Fallback 1**: User opens Xcode.app and creates the project skeleton manually following exact instructions, then the agent takes over file authoring. Adds 15-30 min user time per major target addition (M1, M2, M6).
- **Fallback 2**: Use Tuist instead (Option B). Same operational profile, more complexity.

## Approval

Awaiting user signal to proceed.
