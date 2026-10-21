import Cocoa

extension MissionControlHoverService {
    func fullscreenDisplayID(at point: CGPoint) -> CGDirectDisplayID? {
        ScreenGeometry.screenContaining(axPoint: point)?
            .deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func fullscreenSpace(at point: CGPoint) -> MissionControlSpace? {
        guard isMissionControlSpaceControl(at: point),
              let displayID = fullscreenDisplayID(at: point),
              let index = accessibilityService.getMissionControlSpaceButtonIndex(at: point) else { return nil }
        let spaces = spaceService.managedSpaces(on: displayID)
        guard spaces.indices.contains(index), spaces[index].windowID != nil,
              spaces[index].processID != nil else { return nil }
        return spaces[index]
    }

    func fullscreenWindow(at point: CGPoint) -> [String: Any]? {
        guard isTracking, isSessionEnabled, isMissionControlActive || isMissionControlActiveProvider(),
              let space = fullscreenSpace(at: point), let windowID = space.windowID,
              let processID = space.processID else { return nil }
        return [kCGWindowNumber as String: windowID, kCGWindowOwnerPID as String: processID]
    }

    func beginFullscreenSpaceDrag(at point: CGPoint) {
        guard let space = fullscreenSpace(at: point) else { return }
        fullscreenSpaceDrag = MissionControlFullscreenDrag(
            space: space, startedAt: CACurrentMediaTime(), startPoint: point
        )
    }

    func updateFullscreenSpaceDrag(at point: CGPoint) {
        guard var drag = fullscreenSpaceDrag, drag.destinationSpaceID == nil else { return }
        if hypot(point.x - drag.startPoint.x, point.y - drag.startPoint.y) >= 12 {
            drag.hasDragged = true
            fullscreenSpaceDrag = drag
        }
    }

    func endFullscreenSpaceDrag(at point: CGPoint) {
        guard var drag = fullscreenSpaceDrag, drag.destinationSpaceID == nil else { return }
        guard drag.hasDragged, isTracking, isSessionEnabled,
              !isMissionControlSpaceControl(at: point),
              let displayID = fullscreenDisplayID(at: point),
              let destination = spaceService.activeDisplaySpaces()[displayID],
              spaceService.managedSpaces(on: displayID).contains(where: { $0.id == destination && $0.type == 0 }) else {
            fullscreenSpaceDrag = nil
            return
        }
        drag.destinationSpaceID = destination
        drag.destinationDisplayID = displayID
        fullscreenSpaceDrag = drag
        AppLogger.missionControl.info("Fullscreen drop targets desktop: \(destination, privacy: .public)")
        finishFullscreenSpaceExit(startedAt: drag.startedAt, remainingAttempts: 20)
    }

    /// Capture the displayed desktop before Escape restores a fullscreen Space.
    func fullscreenExitContext(windowID: CGWindowID, at point: CGPoint) -> MissionControlFullscreenDrag? {
        guard let displayID = fullscreenDisplayID(at: point),
              let destination = spaceService.activeDisplaySpaces()[displayID] else { return nil }
        let spaces = spaceService.managedSpaces(on: displayID)
        guard spaces.contains(where: { $0.id == destination && $0.type == 0 }),
              let source = spaces.first(where: { $0.windowID == windowID }) else { return nil }
        var context = MissionControlFullscreenDrag(space: source, startedAt: CACurrentMediaTime(), startPoint: point)
        context.destinationSpaceID = destination
        context.destinationDisplayID = displayID
        return context
    }

    /// Run only during this transition. New input or stop cancels the captured
    /// identity; overview exit/reentry alone must not strand a completed drop.
    func finishFullscreenSpaceExit(startedAt: TimeInterval, remainingAttempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.isTracking, self.isSessionEnabled,
                  var context = self.fullscreenSpaceDrag, context.startedAt == startedAt,
                  let windowID = context.space.windowID, let processID = context.space.processID,
                  let destination = context.destinationSpaceID,
                  let displayID = context.destinationDisplayID else { return }
            let sourceExists = self.spaceService.managedSpaces(on: context.space.displayID)
                .contains(where: { $0.id == context.space.id })
            let memberships = self.spaceService.spaceIDs(for: windowID)
            if !sourceExists, memberships.contains(destination) {
                self.fullscreenSpaceDrag = nil
                AppLogger.missionControl.info("Fullscreen window restored to desktop: \(destination, privacy: .public)")
                return
            }
            if !sourceExists, !memberships.isEmpty, !context.moveRequested {
                context.moveRequested = true
                self.fullscreenSpaceDrag = context
                _ = self.spaceService.moveWindow(windowID, processID: processID, to: destination, on: displayID)
            }
            guard remainingAttempts > 1 else {
                self.fullscreenSpaceDrag = nil
                AppLogger.missionControl.warning("Fullscreen desktop restoration timed out")
                return
            }
            self.finishFullscreenSpaceExit(startedAt: startedAt, remainingAttempts: remainingAttempts - 1)
        }
    }
}
