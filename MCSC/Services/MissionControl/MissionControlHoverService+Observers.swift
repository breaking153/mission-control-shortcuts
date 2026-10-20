import ApplicationServices
import Cocoa

extension MissionControlHoverService {
    static let dockNotifications = [
        "AXExposeShowAllWindows",
        "AXExposeShowFrontWindows",
        "AXExposeExit",
        "AXExposeShowDesktop"
    ]

    func setupDockObserver() {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else {
            AppLogger.dock.error("Dock process not found for AXObserver")
            return
        }

        let pid = dockApp.processIdentifier
        var observer: AXObserver?
        let result = AXObserverCreate(pid, { _, _, notification, refcon in
            guard let refcon else { return }
            let service = Unmanaged<MissionControlHoverService>.fromOpaque(refcon).takeUnretainedValue()
            let notif = notification as String
            MainActor.assumeIsolated {
                service.handleDockNotification(notif)
            }
        }, &observer)

        guard result == .success, let obs = observer else {
            AppLogger.dock.error("Failed to create AXObserver for Dock: \(result.rawValue)")
            return
        }

        let dockElement = AXUIElementCreateApplication(pid)
        self.dockAXElement = dockElement

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        for notif in Self.dockNotifications {
            let addResult = AXObserverAddNotification(obs, dockElement, notif as CFString, refcon)
            if addResult != .success {
                AppLogger.dock.warning("Failed to add observer for \(notif): \(addResult.rawValue)")
            }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        self.axObserver = obs
    }

    func stopDockObserver() {
        if let obs = axObserver {
            if let dockElement = dockAXElement {
                for notif in Self.dockNotifications {
                    AXObserverRemoveNotification(obs, dockElement, notif as CFString)
                }
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
            self.axObserver = nil
            self.dockAXElement = nil
        }
    }

    func handleActivated() {
        guard !isMissionControlActive else { return }
        overviewSessionGeneration &+= 1
        fullscreenRequestGeneration &+= 1
        AppLogger.missionControl.info("Overview tracking session activated")
        debugLog("MissionControlHoverService.handleActivated called", category: AppLogger.missionControl)
        isMissionControlActive = true
        isLabelDismissalPending = false
        entryLabelDeadline = areWindowLabelsEnabled ? CACurrentMediaTime() + 0.7 : nil
        entryLabelEarlyRefreshesRemaining = areWindowLabelsEnabled ? 24 : 0
        requireStableLabelLayout()
        lastKnownSpaceID = spaceService.currentSpaceID()

        guard isSessionEnabled else { return }

        startWindowFetchTimer()
        fetchWindows()
        startKeyboardSession()

        if let mouseLocation = CGEvent(source: nil)?.location {
            updateOverlay(at: mouseLocation)
        }
    }

    func handleDeactivated() {
        overviewSessionGeneration &+= 1
        AppLogger.missionControl.info("Overview tracking session deactivated")
        debugLog("MissionControlHoverService.handleDeactivated called", category: AppLogger.missionControl)
        isMissionControlActive = false
        isLabelDismissalPending = false
        isOverviewGestureInProgress = false
        clearWindowLabelEntryScheduling()
        requireStableLabelLayout()
        missionControlSpacesBarFrames.removeAll(keepingCapacity: false)
        isDragging = false
        isMouseDown = false
        pressedPreviewWindowID = nil
        isSpaceTransitioning = false
        spaceTransitionTimeoutTimer?.invalidate()
        spaceTransitionTimeoutTimer = nil
        lastKnownSpaceID = nil
        stopWindowFetchTimer()
        hideAllOverlays()
        stopKeyboardSession()
        windows = []
        currentMatches = []
        searchSession = WindowSearchSession()
    }

    func handleDockNotification(_ notification: String) {
        debugLog("handleDockNotification: \(notification)", category: AppLogger.dock)
        switch notification {
        case "AXExposeExit", "AXExposeShowDesktop":
            missionControlService?.markActive(false)
            handleDeactivated()
        case "AXExposeShowAllWindows", "AXExposeShowFrontWindows":
            missionControlService?.markActive(true)
            handleActivated()
        default:
            break
        }
    }
}
