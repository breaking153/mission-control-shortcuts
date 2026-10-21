import Cocoa

extension MissionControlHoverService {
    func handleMouseDown(at location: CGPoint) -> Bool {
        fullscreenSpaceDrag = nil
        if consumesCloseButtonMouseUp {
            cancelCloseButtonPress()
            consumesCloseButtonMouseUp = false
        }
        guard isTracking && isSessionEnabled, isMissionControlActive || isMissionControlActiveProvider() else {
            hideAllOverlays()
            return false
        }

        beginFullscreenSpaceDrag(at: location)
        guard isEnabled, let rect = overlayRect, rect.contains(location), overlay.isVisible,
              let action = overlay.action(at: location),
              let window = currentHoveredWindow else {
            debugLog(
                "handleMouseDown: click at \(location) outside overlay - hiding overlays and preparing drag",
                category: AppLogger.missionControl
            )
            let previewID = labelsOverlay?.windowID(at: location)
                ?? (currentPreviewFrame?.contains(location) == true
                    ? currentHoveredWindow?[kCGWindowNumber as String] as? CGWindowID : nil)
            isMouseDown = true
            pressedPreviewWindowID = previewID
            if let previewID {
                // Native preview selection happens on mouse-up; keep the other
                // labels visible while this press can still become a drag.
                clearWindowLabelEntryScheduling()
                labelsOverlay?.setDraggedWindowID(previewID)
                hideCloseOverlay()
                hideSearchOverlay()
                return false
            }
            prepareForOverviewDismissal()
            // Spaces controls can add/remove desktops without dismissing
            // the overview. Resume only after its new layout is stable.
            if isMissionControlSpaceControl(at: location) {
                isLabelDismissalPending = false
                beginSpaceTransition()
            }
            return false
        }

        debugLog(
            "handleMouseDown: click at \(location) on overlay action \(action)",
            category: AppLogger.missionControl
        )
        HapticService.perform(.pinchIn)
        if action == .close, beginCloseButtonPress(on: window, at: location) {
            return true
        }
        executeAction(mode: action, on: window)
        return true
    }

    func handleMouseDragged(at location: CGPoint) {
        updateFullscreenSpaceDrag(at: location)
        if consumesCloseButtonMouseUp {
            updateCloseButtonPress(at: location)
            return
        }
        guard isTracking, isSessionEnabled, isMissionControlActive, isMouseDown else { return }
        isDragging = true
        hideCloseOverlay()
        hideSearchOverlay()
    }

    func handleMouseUp(at location: CGPoint) {
        endFullscreenSpaceDrag(at: location)
        guard isTracking, isSessionEnabled else {
            isDragging = false
            isMouseDown = false
            pressedPreviewWindowID = nil
            return
        }
        let wasDragging = isDragging
        let selectedPreview = pressedPreviewWindowID != nil
        isDragging = false
        isMouseDown = false
        pressedPreviewWindowID = nil
        if wasDragging {
            hideCloseOverlay()
            beginSpaceTransition()
        } else if selectedPreview {
            prepareForOverviewDismissal()
        } else if !isLabelDismissalPending, isMissionControlActive {
            beginSpaceTransition()
        }
    }
}
