# Mission Control Secure Input Compatibility Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline.

**Goal:** Keep configured Mission Control Command shortcuts working while Secure Input is held by another app.

**Architecture:** A lazily created service owns a Carbon handler and successfully registered bindings during overview only. The view model routes native hotkeys through the existing handler and lets the event tap pass owned chords to avoid duplicate execution.

**Tech Stack:** Existing Swift/AppKit, HIToolbox registered-hotkey APIs, Unified Logging.

**Spec:** `docs/superpowers/specs/2026-10-25-mission-control-secure-hotkeys-design.md`

## Global Constraints

- No repository test files: AGENTS.md overrides generic TDD test-file instructions; live temporary diagnostics already reproduce the failure.
- No dependency, idle timer, retained AX tree, password access, or changes to Bitwarden.
- Preserve existing shortcut settings and target resolution.
- Measure physical footprint against the same cold baseline; disclose the strict decimal 13 MB result.

## Review Focus

- Native and raw delivery must execute one action per press.
- An event queued from an old session must not match a new registration.
- Exit and stop must unregister every successfully registered hotkey.
- Registration conflict must preserve the raw-event path.
- Dispatch must force-check overview state before acting on a preview.

### Task 1: Add native overview shortcuts and validate compatibility

**Files:**
- Create `MCSC/Services/EventTap/MissionControlShortcutService.swift`: native registration and cleanup.
- Modify `MCSC/ViewModels/ShortcutViewModel.swift`: lazy ownership and overview/configuration/stop lifecycle.
- Modify `MCSC/ViewModels/ShortcutViewModel+EventHandlers.swift`: shared action routing, raw/native delivery selection.
- Create `MCSC/ViewModels/ShortcutViewModel+MissionControlShortcuts.swift`: registration synchronization and native dispatch gate.
- Update `docs/DIAGNOSTICS.md` and `docs/MISSION_CONTROL.md`: exact failure, PID attribution limits, compatibility and limitations.

**Interfaces:**
- Service consumes `Set<ShortcutBinding>` and emits `onShortcut: ((ShortcutBinding, CGPoint) -> Void)?`.
- Service produces `start(bindings:)`, `stop()`, `owns(keyCode:flags:)`, and `registeredCount`.
- View model produces `handleShortcut(keyCode:flags:location:) -> Bool` and `syncMissionControlShortcuts()`.

- [x] Reproduce Secure Input starvation with the installed build and verify Bitwarden foreground/background/hidden transitions.
- [x] Prove native chord delivery with Secure Input off and on in actual overview.
- [x] Implement the service, routing selection and lifecycle, using weak callbacks and monotonically increasing IDs.
- [x] Format, lint, Release build and analyze; expected exit 0, no format changes, no lint errors.
- [x] Live-verify owned-window close/minimize, repeated entry/exit, native fullscreen and outside-overview delivery; expected one action and no leftover registrations.
- [x] Compare cold memory, obtain fresh code review, address material findings, document actual evidence.
- [x] Install the verified build locally with a backup and verify Accessibility/native shortcuts after authorization if required.

## Execution record

Reuse the clean current checkout on a `codex/` branch, following the desktop preference for reusing the current checkout. The feature repairs the existing shortcut contract. Root-cause and compatibility proofs are retained under `~/Library/Logs/MCSC/secure-input-investigation-20261025/`. No unit/integration/UI test files will be introduced.


### Verification evidence

- Release build and analyzer succeeded; SwiftFormat lint: 0/101 files need formatting. SwiftLint has no errors and retains pre-existing warnings. No test files added.
- Actual Mission Control: normal Command-W closes exactly one owned window; Command-E minimizes with Secure Input still enabled; Command-W works after six normal and ten rapid overview cycles while Secure Input remains enabled.
- Fullscreen entry started with Secure Input enabled and succeeded; the fullscreen Space tile Command-R exit also succeeded. Ordinary foreground Command-W worked after overview exited and native registrations were removed.
- An early rapid-cycle probe attempted AX preview lookup before WindowManager finished its animation/tree rebuild. Waiting for the owned preview resolved the automation timing failure; no production change was needed.
- Cold physical footprint: original 12,780,480 bytes; final candidate 12,895,168 bytes (delta 114,688 bytes), both below decimal 13 MB. Interaction/long-running memory is a separate measurement.
- Fresh reviewer found a replaced-overview reentrancy edge; registration generation now rejects that old event. No remaining actionable findings. A chord at the narrow exit-notification boundary can be discarded rather than replayed to an unrelated window; this is logged and documented.
- Evidence directory: `~/Library/Logs/MCSC/secure-input-investigation-20261025/`.

- Local verified bundle installed at `/Applications/MCSC.app` with an official v0.9.3 backup. Binary SHA256 `bb7e19e698068774ae5f6e89acf696ffa30d098ebd92757723742e52858202a1` matches the validated candidate. Normal LaunchServices startup runs, but Accessibility denies the new signature; final normal-launch verification awaits user reauthorization. This is a local unreleased fix based on v0.9.3; no new release was published.

- User reauthorized the installed bundle. A normal LaunchServices restart (PID 54421) confirmed Accessibility trusted and hover tracking active; cold physical footprint was 12,878,760 bytes. The installed binary independently passed normal/secure close, secure minimize, fullscreen, six ordinary overview cycles, ten rapid cycles with Secure Input still enabled, and ordinary foreground Command-W. Native registration/unregistration log counts balanced (19 sessions each). Owned test windows were removed; MCSC remains running outside overview with no active native reservations.
