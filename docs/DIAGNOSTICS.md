# MCSC Diagnostics & AI Agent Audit Guide

> **Note for AI Agents:**
> MCSC operates headlessly in the background. Diagnostics are completely zero-touch and designed specifically for automated auditing by AI agents when the app misbehaves or crashes. There is intentionally no user-facing UI for exporting diagnostics.

---

## 1. Diagnostic Architecture

MCSC uses **Apple Unified Logging (`os.Logger`)** and **`OSLogStore`** with zero heap memory overhead during normal operation (under the 13 MB strict limit defined in `AGENTS.md`).

- **Log Subsystem:** `sj010.MCSC`
- **In-Memory Ring Buffer:** Managed by macOS kernel.
- **On Fault / Crash:** Trapped via `NSSetUncaughtExceptionHandler` & fatal signal handlers (`SIGSEGV`, `SIGABRT`, `SIGBUS`, `SIGILL`) which immediately dump crash backtraces and recent logs to disk.
- **On App Termination:** Automatic snapshot saved to disk via `NSApplication.willTerminateNotification`.

---

## 2. On-Disk Artifact Locations

When auditing an issue or investigating user bug reports, inspect these locations first:

| Artifact Path | Description | Format |
|---|---|---|
| `~/Library/Logs/MCSC/diagnostic_report.jsonl` | Most recent structured event logs extracted via `OSLogStore` | JSON Lines (`.jsonl`) |
| `~/Library/Logs/MCSC/crash.log` | Last fatal exception / signal backtrace | Plain text |
| `~/Library/Logs/DiagnosticReports/MCSC-*.ips` | macOS system crash report with full thread states | Apple `.ips` / JSON |

---

## 3. Querying Live & Historical Logs with CLI

AI agents with shell access can query the Apple Unified Logging store directly using `log show` and `log stream`.

### A. Inspect Last 10 Minutes of MCSC Activity
```bash
log show --predicate 'subsystem == "sj010.MCSC"' --info --debug --last 10m --style json
```

### B. Live Stream During Reproduction
```bash
log stream --predicate 'subsystem == "sj010.MCSC"' --info --debug
```

### C. Filter by Component Category
```bash
# Keyboard Event Tap & Shortcuts
log show --predicate 'subsystem == "sj010.MCSC" AND category == "eventTap"' --last 15m

# Trackpad Gestures & Recognition
log show --predicate 'subsystem == "sj010.MCSC" AND category == "gesture"' --last 15m

# Accessibility (AX) & Window Hierarchy
log show --predicate 'subsystem == "sj010.MCSC" AND category == "accessibility"' --last 15m

# Mission Control State Transitions
log show --predicate 'subsystem == "sj010.MCSC" AND category == "missionControl"' --last 15m

# Background Diagnostics & Heartbeat
log show --predicate 'subsystem == "sj010.MCSC" AND category == "diagnostics"' --last 15m
```

---

## 4. Log Categories & Troubleshooting Guide

### `eventTap`
* **Normal:**
  * `Event tap created and attached to run loop.`
  * `Shortcut matched and consumed: keyCode=...`
* **Issue indicators:**
  * `Event tap disabled by system (timeout); re-enabled.` -> System dropped event tap due to slow AX IPC or main thread delay.
  * `Failed to create event tap` -> Accessibility permissions missing.
  * Tap enabled and Accessibility trusted, but no shortcut matches -> check
    `IsSecureEventInputEnabled()`. Secure Input can starve raw keyboard taps
    without disabling the tap itself. Restarting MCSC or toggling its permission
    does not release another application's Secure Input ownership.
  * `Mission Control native shortcuts registered: count=...` / `unregistered`
    -> configured Command chords are reserved only during overview, including
    when Secure Input is enabled. A registration warning reports a conflict;
    that chord retains the previous raw-tap path and its Secure Input limitation.

#### Repeated failure after lock/unlock: Bitwarden investigation (2026-10-25)

With Bitwarden 2026.10.0 (71688), a controlled foreground/background/hide
sequence reproduced Secure Input remaining enabled after Bitwarden lost focus.
Hiding the same running Bitwarden process disabled Secure Input; the unchanged
MCSC v0.9.3 then received Command-W and closed exactly one disposable window.
This identifies the observed holder by a reversible state change. The
`kCGSSessionSecureInputPID` values in IORegistry/session dictionaries alone are
not reliable holder attribution: they differed and could track loginwindow or
the foreground application during this investigation.

MCSC uses system-registered hotkeys during Mission Control to avoid dependence
on raw keyboard interception. It does not hide Bitwarden automatically, change
vault/autolock settings, or disable another process's Secure Input. Ordinary
type-to-search and shortcuts outside overview still depend on raw event access.
For those features, hide the application holding Secure Input or resolve its
password prompt. A chord pressed in the brief interval after overview closes
but before its deactivation notification/scan can be discarded: native dispatch
unregisters and refuses to act on an ordinary window. MCSC does not replay the
chord through Secure Input; retry after the transition. See the matching upstream
[Bitwarden issue](https://github.com/bitwarden/clients/issues/21964) and Apple's
[Secure Event Input guidance](https://developer.apple.com/library/archive/technotes/tn2150/_index.html).

### `gesture`
* **Normal:**
  * `Gesture recognized: swipeLeft, isCmd=false`
  * `Executing gesture action for target: window(...)`
* **Issue indicators:**
  * `Gesture ignored (no routed action)` -> Gesture fired but target under cursor did not match binding or was disabled in configuration.

### `accessibility`
* **Normal:**
  * Clean return of window/dock elements.
* **Issue indicators:**
  * `performAction 'AXPress' failed with code -25204` -> Target UI element rejected action.
  * `setFrame failed (pos=..., size=...)` -> Target application prevented programmatic resizing or repositioning.

### `missionControl`
* **Normal:**
  * `Mission Control active state changed: true` / `false`
* **Issue indicators:**
  * Latch desync: Dock observer missed close notification. Check heuristic scan self-correction.

---

## 5. Audit Workflow for AI Agents

When the user asks you to diagnose an issue:

1. **Check Crash Reports:**
   ```bash
   cat ~/Library/Logs/MCSC/crash.log
   ls -lat ~/Library/Logs/DiagnosticReports/MCSC*
   ```
2. **Read Diagnostic Log:**
   ```bash
   tail -n 100 ~/Library/Logs/MCSC/diagnostic_report.jsonl
   ```
3. **Inspect Unified Log stream for PID / Subsystem:**
   ```bash
   log show --predicate 'subsystem == "sj010.MCSC"' --info --debug --last 5m
   ```
4. **Correlate Sequence:**
   Trace `eventTap` (key event received) -> `accessibility` (target element resolved) -> `action` (executed or dropped).
