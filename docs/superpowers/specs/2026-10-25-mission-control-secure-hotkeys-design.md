# Mission Control shortcuts during Secure Input

Restore configured Command shortcuts inside Mission Control when another app holds macOS Secure Input. On 25 October, Bitwarden 2026.10.0 reproducibly held Secure Input after moving to the background; hiding it released the state, and the unchanged MCSC then closed an owned window with Command-W. Registry and current-session PID fields proved unreliable for attributing ownership.

## Approach

Use public Carbon registered hotkeys only during an active Mission Control session. A controlled probe received a registered chord in Mission Control with Secure Input both off and on. Keep the existing action router, target isolation, gestures, labels, and controls. The raw event tap passes registered combinations through so one press executes once; failed registrations retain the existing path. Unregister on deactivation and stop. Native dispatch force-checks the current overview before acting.

Alternatives: changing Bitwarden background/autolock settings affects password-manager behavior; forcibly clearing another process's Secure Input violates its ownership. Neither is needed for this compatibility fix. Hiding Bitwarden remains a recovery method, not an automatic action MCSC takes.

## Constraints

No new external dependency, background timer, test file, diagnostic UI, password access, or modification of Bitwarden. HIToolbox is already mapped by MCSC; native registrations and their handler exist only during overview. Compare cold physical footprint before and after. The established baseline already misses a strict decimal 13 MB ceiling; disclose measurements rather than relabeling them. Normal shortcuts outside overview retain the existing mechanism. Plain type-to-search is still subject to macOS Secure Input.

## Validation

Verify Command-W closes exactly one owned window with Secure Input off/on, Command-E minimizes one, repeated overview entry and exit release registrations, configurable Shift bindings refresh, and outside-overview shortcuts reach the owned foreground app. Preserve native fullscreen routing, window controls, gestures, label exit behavior, and desktop isolation. Use live disposable-window automation outside the repository as authorized; add no test files.
