import Cocoa

extension MissionControlHoverService {
    /// WindowServer acknowledges AXFullScreen during overview but discards the
    /// transition. Exit first, then apply it to the captured window identity.
    func requestFullscreenAfterOverviewExit(on window: [String: Any]) {
        guard let windowID = window[kCGWindowNumber as String] as? CGWindowID,
              let processID = window[kCGWindowOwnerPID as String] as? pid_t,
              let spaceID = spaceService.currentSpaceID() else { return }
        fullscreenRequestGeneration &+= 1
        let request = fullscreenRequestGeneration
        prepareForOverviewDismissal()
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
        finishFullscreenRequest(windowID: windowID, processID: processID, spaceID: spaceID,
                                request: request, remainingAttempts: 10)
    }

    private func finishFullscreenRequest(
        windowID: CGWindowID, processID: pid_t, spaceID: Int,
        request: UInt, remainingAttempts: Int
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.isTracking, self.isEnabled,
                  self.fullscreenRequestGeneration == request,
                  self.spaceService.currentSpaceID() == spaceID else { return }
            let active = self.missionControlService?.checkMissionControlActive(force: true)
                ?? self.isMissionControlActiveProvider()
            guard self.fullscreenRequestGeneration == request else { return }
            if active {
                if remainingAttempts > 1 {
                    self.finishFullscreenRequest(windowID: windowID, processID: processID,
                                                 spaceID: spaceID, request: request,
                                                 remainingAttempts: remainingAttempts - 1)
                }
                return
            }
            guard let app = NSRunningApplication(processIdentifier: processID), !app.isTerminated,
                  let target = self.accessibilityService.getWindow(forWindowID: windowID) else { return }
            var targetPID: pid_t = 0
            guard AXUIElementGetPid(target, &targetPID) == .success, targetPID == processID else { return }
            let window: [String: Any] = [kCGWindowNumber as String: windowID,
                                         kCGWindowOwnerPID as String: processID]
            AppLogger.missionControl.info("Overview fullscreen request executing: window=\(windowID, privacy: .public)")
            MissionControlWindowActions.performFullscreen(on: window, accessibilityService: self.accessibilityService)
        }
    }
}
