import Cocoa

extension MissionControlHoverService {
    func beginCloseButtonPress(on window: [String: Any], at point: CGPoint) -> Bool {
        guard let windowID = window[kCGWindowNumber as String] as? CGWindowID,
              let processID = window[kCGWindowOwnerPID as String] as? pid_t,
              let frame = overlay.buttonFrame(at: point) else { return false }
        cancelCloseButtonPress()
        let press = MissionControlCloseButtonPress(
            windowID: windowID, processID: processID,
            sessionGeneration: overviewSessionGeneration, buttonFrame: frame,
            deadline: CACurrentMediaTime() + MissionControlCloseButtonPress.holdDuration
        )
        closeButtonPress = press
        AppLogger.missionControl
            .info(
                "Close button press began: window=\(windowID, privacy: .public), session=\(self.overviewSessionGeneration, privacy: .public)"
            )
        consumesCloseButtonMouseUp = true
        clearWindowLabelEntryScheduling()
        labelsOverlay?.setDraggedWindowID(windowID)
        overlay.setLongPressing(true)
        closeButtonHoldTimer = Timer.scheduledCommon(
            interval: MissionControlCloseButtonPress.holdDuration,
            repeats: false, tolerance: 0.01
        ) { [weak self] _ in
            guard let self, self.closeButtonPress?.deadline == press.deadline else { return }
            self.closeButtonHoldTimer = nil
            guard var current = self.closeButtonPress,
                  let point = CGEvent(source: nil)?.location else {
                self.cancelCloseButtonPress()
                return
            }
            let action = current.action(at: point, now: CACurrentMediaTime(), isRelease: false)
            self.closeButtonPress = current
            self.overlay.setLongPressing(false)
            if let action {
                self.performCloseButtonPress(action, press: current)
            }
        }
        return true
    }

    func updateCloseButtonPress(at point: CGPoint) {
        guard var press = closeButtonPress else { return }
        press.updatePointer(point)
        closeButtonPress = press
        if press.isCancelled {
            closeButtonHoldTimer?.invalidate()
            closeButtonHoldTimer = nil
            overlay.setLongPressing(false)
        }
    }

    /// Swallow the matching release even if exit/Space changes cancelled the hold.
    func finishCloseButtonPress(at point: CGPoint) -> Bool {
        guard consumesCloseButtonMouseUp else { return false }
        consumesCloseButtonMouseUp = false
        var press = closeButtonPress
        let remaining = press.map { $0.deadline - CACurrentMediaTime() } ?? -1
        AppLogger.missionControl
            .info(
                "Close button released: remaining=\(remaining, privacy: .public), cancelled=\(press?.isCancelled ?? true, privacy: .public)"
            )
        cancelCloseButtonPress()
        if let action = press?.action(at: point, now: CACurrentMediaTime(), isRelease: true), let press {
            performCloseButtonPress(action, press: press)
        } else if isTracking, isMissionControlActive, !isLabelDismissalPending {
            fetchWindows()
            updateOverlay(at: point, forceRefresh: true)
        }
        return true
    }

    func cancelCloseButtonPress() {
        guard closeButtonPress != nil || closeButtonHoldTimer != nil else { return }
        closeButtonHoldTimer?.invalidate()
        closeButtonHoldTimer = nil
        closeButtonPress = nil
        labelsOverlay?.setDraggedWindowID(nil)
        overlay.setLongPressing(false)
    }

    private func isCurrentCloseButtonPress(_ press: MissionControlCloseButtonPress) -> Bool {
        press.sessionGeneration == overviewSessionGeneration
            && isTracking && isEnabled && isMissionControlActive
            && !isSpaceTransitioning && !isOverviewGestureInProgress && !isLabelDismissalPending
    }

    private func performCloseButtonPress(
        _ action: MissionControlCloseButtonPress.Action, press: MissionControlCloseButtonPress
    ) {
        guard isCurrentCloseButtonPress(press),
              missionControlService?.checkMissionControlActive(force: true) ?? isMissionControlActiveProvider(),
              isCurrentCloseButtonPress(press),
              spaceService.isWindowOnCurrentSpace(windowID: press.windowID),
              let window = windows.first(where: {
                  ($0[kCGWindowNumber as String] as? CGWindowID) == press.windowID
                      && ($0[kCGWindowOwnerPID as String] as? pid_t) == press.processID
              }) else {
            AppLogger.missionControl.info("Close button action discarded: session or target changed")
            return
        }
        switch action {
        case .closeWindow:
            executeAction(mode: .close, on: window)
        case .quitApplication:
            guard let app = NSRunningApplication(processIdentifier: press.processID), app.isSafeTargetProcess else {
                cancelCloseButtonPress()
                return
            }
            HapticService.perform(.pinchIn)
            AppLogger.missionControl
                .info("Close button hold requested application quit: pid=\(press.processID, privacy: .public)")
            // A normal quit lets the owning application handle unsaved documents.
            _ = app.terminate()
            hideAllOverlays()
        }
    }
}
