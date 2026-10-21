import Cocoa

extension MissionControlHoverService {
    /// WindowServer acknowledges AXFullScreen during overview but discards the
    /// transition. Exit first, then apply it to the captured window identity.
    func requestFullscreenAfterOverviewExit(on window: [String: Any]) {
        let point = CGEvent(source: nil)?.location ?? .zero
        guard let windowID = window[kCGWindowNumber as String] as? CGWindowID,
              let processID = window[kCGWindowOwnerPID as String] as? pid_t,
              let displayID = fullscreenDisplayID(at: point),
              let spaceID = spaceService.activeDisplaySpaces()[displayID] else { return }
        let allowedSpaces = spaceService.spaceIDs(for: windowID) + [spaceID]
        let exitContext = fullscreenExitContext(windowID: windowID, at: point)
        fullscreenSpaceDrag = nil
        fullscreenRequestGeneration &+= 1
        let request = fullscreenRequestGeneration
        prepareForOverviewDismissal()
        let source = CGEventSource(stateID: .hidSystemState)
        // A held Command key must not turn the dismissal into Command-Escape.
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
        finishFullscreenRequest(windowID: windowID, processID: processID, displayID: displayID,
                                allowedSpaces: allowedSpaces, exitContext: exitContext,
                                request: request, remainingAttempts: 15)
    }

    private func finishFullscreenRequest(
        windowID: CGWindowID, processID: pid_t, displayID: CGDirectDisplayID,
        allowedSpaces: [Int], exitContext: MissionControlFullscreenDrag?,
        request: UInt, remainingAttempts: Int
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.isTracking, self.isSessionEnabled,
                  self.fullscreenRequestGeneration == request,
                  let currentSpace = self.spaceService.activeDisplaySpaces()[displayID],
                  allowedSpaces.contains(currentSpace) else { return }
            let active = self.missionControlService?.checkMissionControlActive(force: true)
                ?? self.isMissionControlActiveProvider()
            guard self.fullscreenRequestGeneration == request else { return }
            if active {
                if remainingAttempts > 1 {
                    self.finishFullscreenRequest(windowID: windowID, processID: processID,
                                                 displayID: displayID, allowedSpaces: allowedSpaces,
                                                 exitContext: exitContext, request: request,
                                                 remainingAttempts: remainingAttempts - 1)
                }
                return
            }
            guard let app = NSRunningApplication(processIdentifier: processID), !app.isTerminated else { return }
            guard let target = self.accessibilityService.getWindow(forWindowID: windowID) else {
                if remainingAttempts > 1 {
                    self.finishFullscreenRequest(windowID: windowID, processID: processID,
                                                 displayID: displayID, allowedSpaces: allowedSpaces,
                                                 exitContext: exitContext, request: request,
                                                 remainingAttempts: remainingAttempts - 1)
                }
                return
            }
            var targetPID: pid_t = 0
            guard AXUIElementGetPid(target, &targetPID) == .success, targetPID == processID else { return }
            let window: [String: Any] = [kCGWindowNumber as String: windowID,
                                         kCGWindowOwnerPID as String: processID]
            AppLogger.missionControl.info("Overview fullscreen request executing: window=\(windowID, privacy: .public)")
            MissionControlWindowActions.performFullscreen(on: window, accessibilityService: self.accessibilityService)
            if let exitContext {
                self.fullscreenSpaceDrag = exitContext
                self.finishFullscreenSpaceExit(startedAt: exitContext.startedAt, remainingAttempts: 20)
            }
        }
    }
}
