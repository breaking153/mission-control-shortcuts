import ApplicationServices
import Cocoa

extension MissionControlHoverService {
    func updateWindowButtonScale() {
        if isMissionControlActive, let point = CGEvent(source: nil)?.location {
            updateOverlay(at: point, forceRefresh: true)
        }
    }

    func startWindowFetchTimer() {
        guard windowFetchTimer == nil else { return }
        windowFetchTimer = Timer.scheduledCommon(
            interval: HoverServiceTiming.windowPoll,
            repeats: true,
            tolerance: HoverServiceTiming.windowPollTolerance
        ) { [weak self] _ in
            guard let self else { return }
            self.isWindowFetchTimerFiring = true
            defer { self.isWindowFetchTimerFiring = false }
            self.fetchWindows()
            self.refreshCloseOverlayAfterWindowFetch()
        }
    }

    /// Retry after transient AX snapshots even if the pointer never moves.
    func refreshCloseOverlayAfterWindowFetch() {
        guard isTracking, isEnabled, isMissionControlActive,
              !isDragging, !isMouseDown, !consumesCloseButtonMouseUp, !isSpaceTransitioning,
              !isOverviewGestureInProgress, !isLabelDismissalPending,
              isMissionControlActiveProvider(),
              let location = CGEvent(source: nil)?.location else { return }
        updateOverlay(at: location, forceRefresh: true)
    }

    /// Fetches and filters the active window list for Mission Control tracking.
    ///
    /// ## macOS 27 WindowManager Multi-Space Isolation
    /// On macOS 27+, `com.apple.WindowManager` manages Mission Control at Layer 19.
    /// Crucially, its AX accessibility hierarchy retains preview tiles (`AXButton` elements
    /// with a `"wid"` attribute) for **all desktop spaces simultaneously** at their virtual
    /// desktop layout coordinates.
    ///
    /// If off-space windows are included in `windows`, `accessibilityService.getMissionControlPreviewTile`
    /// will hit-test and match ghost preview tiles from inactive spaces (e.g. hovering over Desktop 2
    /// hitting a Desktop 1 Ghostty window thumbnail).
    ///
    /// To ensure strict space isolation:
    /// 1. Only windows where `spaceService.isWindowOnCurrentSpace(windowID:) == true` are tracked.
    /// 2. Windows with no explicit space assignment (empty space IDs) belong to all spaces (e.g. floating Finder or
    /// panels).
    /// 3. Layers 0 through 3 are captured so floating utility and tool windows on secondary spaces are retained.
    func fetchWindows() {
        // Frozen by `_testSeedWindows` in unit tests so assertions are
        // deterministic regardless of the host's real window list.
        guard !isTestSeedingEnabled, let list = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return
        }
        cacheMissionControlSpacesBarFrames(from: list)

        let filtered = list.filter { window in
            guard let layer = window[kCGWindowLayer as String] as? Int, layer >= 0, layer <= 3,
                  let owner = window[kCGWindowOwnerName as String] as? String,
                  owner != "Dock", owner != "MCSC", owner != "Window Server", owner != "WindowManager",
                  let wid = window[kCGWindowNumber as String] as? CGWindowID,
                  spaceService.isWindowOnCurrentSpace(windowID: wid) else {
                return false
            }
            // WindowManager can report the *scaled* preview bounds here.
            // Keep small previews for labels and hover actions; AX matching excludes
            // non-preview utility surfaces before anything is drawn.
            let minimumDimension: CGFloat = isMissionControlActive ? 1 : 100
            if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
               let w = bounds["Width"], let h = bounds["Height"], w >= minimumDimension, h >= minimumDimension {
                return true
            }
            return false
        }

        // IDs may be unchanged while titles or preview layout change.
        windows = filtered
        refreshWindowLabels()
    }

    func stopWindowFetchTimer() {
        windowFetchTimer?.invalidate()
        clearWindowLabelEntryScheduling()
        windowFetchTimer = nil
    }

    func clearWindowLabelEntryScheduling() {
        entryLabelDeadline = nil
        entryLabelEarlyRefreshesRemaining = 0
        windowFetchTimer?.tolerance = HoverServiceTiming.windowPollTolerance
    }

    /// Resolve entry snapshots at fixed AX destinations for at most 0.7s.
    /// Its normal 500ms interval resumes as soon as entry finishes.
    func scheduleEarlierEntryLabelRefresh(now: CFTimeInterval) {
        guard isTracking, areWindowLabelsEnabled, isMissionControlActive,
              needsStableLabelLayout, !isDragging, !isMouseDown,
              !isSpaceTransitioning, !isOverviewGestureInProgress, !isLabelDismissalPending,
              isMissionControlActiveProvider(),
              let deadline = entryLabelDeadline, now < deadline,
              entryLabelEarlyRefreshesRemaining > 0,
              let timer = windowFetchTimer, timer.isValid, timer.timeInterval > 0 else { return }
        let delay = min(1.0 / 30, deadline - now)
        guard delay > 0 else { return }
        let wallNow = Date()
        var nextFireDate = timer.fireDate
        if isWindowFetchTimerFiring, nextFireDate <= wallNow {
            // Foundation leaves fireDate at the just-fired deadline until the
            // callback returns. Compare against its next repeating deadline.
            let elapsed = wallNow.timeIntervalSince(nextFireDate)
            let intervals = floor(elapsed / timer.timeInterval) + 1
            nextFireDate = nextFireDate.addingTimeInterval(intervals * timer.timeInterval)
        }
        let earlierFireDate = wallNow.addingTimeInterval(delay)
        guard nextFireDate.timeIntervalSince(earlierFireDate) >= 0.001 else { return }
        timer.tolerance = 0.005
        timer.fireDate = earlierFireDate
        entryLabelEarlyRefreshesRemaining -= 1
    }

    private func finishWindowLabelEntry() {
        clearWindowLabelEntryScheduling()
        needsStableLabelLayout = false
        settlingLabelFrames.removeAll(keepingCapacity: false)
        labelLayoutStableSince = nil
    }

    func labelHoverLocation(at point: CGPoint) -> CGPoint {
        if let rect = overlayRect, rect.contains(point), let frame = currentPreviewFrame {
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        return point
    }

    func cacheMissionControlSpacesBarFrames(from windows: [[String: Any]]) {
        missionControlSpacesBarFrames = windows.compactMap { info in
            guard info[kCGWindowOwnerName as String] as? String == "WindowManager",
                  info[kCGWindowLayer as String] as? Int == 14,
                  info[kCGWindowIsOnscreen as String] as? Bool == true,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  !frame.isEmpty, !frame.isInfinite, !frame.isNull else { return nil }
            return frame
        }
    }

    func requireStableLabelLayout() {
        needsStableLabelLayout = true
        settlingLabelFrames.removeAll(keepingCapacity: false)
        labelLayoutStableSince = nil
    }

    /// Resolve only for a click, after labels have already been ordered out.
    /// The same Spaces controls expose selection and desktop removal actions.
    func isMissionControlSpaceControl(at point: CGPoint) -> Bool {
        // Collapsed Spaces buttons expose expanded AX coordinates on macOS
        // 27. The actual bar surface is already in the existing CG snapshot.
        if missionControlSpacesBarFrames.contains(where: { $0.contains(point) }) {
            return true
        }
        var element = accessibilityService.getElement(at: point)
        for _ in 0 ..< 4 {
            guard let current = element else { return false }
            let identifier: String? = accessibilityService.getAttributeValue(kAXIdentifierAttribute, for: current)
            if identifier?.hasPrefix("mc.spaces") == true {
                return true
            }
            element = accessibilityService.getAttributeValue(kAXParentAttribute, for: current)
        }
        return false
    }

    func setOverviewGestureInProgress(_ inProgress: Bool) {
        guard isOverviewGestureInProgress != inProgress else { return }
        isOverviewGestureInProgress = inProgress
        guard isMissionControlActive else { return }
        beginSpaceTransition()
    }

    /// Runs before the triggering input is passed to WindowServer. Keep the
    /// session active while its canvas exits, but never repaint its labels.
    func prepareForOverviewDismissal() {
        guard isTracking, isMissionControlActive else { return }
        if !isLabelDismissalPending {
            AppLogger.missionControl.info("Overview dismissal prepared")
        }
        isLabelDismissalPending = true
        clearWindowLabelEntryScheduling()
        hideAllOverlays()
    }

    /// Hover actions and persistent labels share a tracking session, but each
    /// presentation feature has its own switch.
    func updateSessionFeatures() {
        guard isTracking else { return }
        guard isSessionEnabled else {
            stopWindowFetchTimer()
            stopKeyboardSession()
            hideAllOverlays()
            return
        }
        guard isMissionControlActive else { return }
        fetchWindows()
        startWindowFetchTimer()
        if keyboardTap == nil {
            startKeyboardSession()
        }
        if let point = CGEvent(source: nil)?.location {
            updateOverlay(at: point)
        }
    }

    /// Entry appears directly at AX destinations. Held preview drags retain the
    /// other panels; hard dismissal and desktop transitions still remove all.
    func refreshWindowLabels() {
        let now = CACurrentMediaTime()
        if let deadline = entryLabelDeadline,
           now >= deadline || entryLabelEarlyRefreshesRemaining <= 0 {
            finishWindowLabelEntry()
        }
        defer { scheduleEarlierEntryLabelRefresh(now: CACurrentMediaTime()) }
        guard isTracking, areWindowLabelsEnabled, isMissionControlActive,
              !isSpaceTransitioning, !isOverviewGestureInProgress, !isLabelDismissalPending,
              isMissionControlActiveProvider() else {
            releaseWindowLabels()
            return
        }

        let activeSpaces = spaceService.activeDisplaySpaces()
        guard !activeSpaces.isEmpty else {
            releaseWindowLabels()
            return
        }
        if !labelDisplaySpaces.isEmpty, labelDisplaySpaces != activeSpaces {
            beginSpaceTransition()
            return
        }
        labelDisplaySpaces = activeSpaces
        if consumesCloseButtonMouseUp {
            if let press = closeButtonPress {
                labelsOverlay?.setDraggedWindowID(press.windowID)
            }
            return
        }
        if isMouseDown || isDragging {
            if let pressedPreviewWindowID {
                labelsOverlay?.setDraggedWindowID(pressedPreviewWindowID)
            } else {
                releaseWindowLabels()
            }
            return
        }

        let byID = Dictionary(windows.compactMap { info -> (CGWindowID, [String: Any])? in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID else { return nil }
            return (id, info)
        }, uniquingKeysWith: { first, _ in first })
        let previews = accessibilityService.getMissionControlPreviews(matchingWindowIDs: Set(byID.keys))
        let isEntering = entryLabelDeadline != nil
        var labels: [MissionControlWindowLabel] = []
        var titlesByProcess: [pid_t: [CGWindowID: String]] = [:]
        var included = Set<CGWindowID>()
        for preview in previews {
            let center = CGPoint(x: preview.frame.midX, y: preview.frame.midY)
            guard preview.frame.width >= 32, preview.frame.height >= 24,
                  let screen = NSScreen.screens.first(where: { ScreenGeometry.axBounds(for: $0).contains(center) }),
                  let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let activeSpace = activeSpaces[display.uint32Value],
                  preview.spaceID == nil || preview.spaceID == activeSpace,
                  !included.contains(preview.windowID),
                  let info = byID[preview.windowID],
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t else { continue }

            // The global window list includes all displays' active spaces.
            // Also check the display containing this particular preview.
            let spaces = spaceService.spaceIDs(for: preview.windowID)
            guard spaces.isEmpty || spaces.contains(activeSpace) else { continue }
            let frame = preview.frame
            let title = windowLabelTitle(
                windowID: preview.windowID, processID: pid, info: info,
                isEntering: isEntering, titlesByProcess: &titlesByProcess
            )
            guard !title.isEmpty else { continue }
            included.insert(preview.windowID)
            labels.append(MissionControlWindowLabel(
                windowID: preview.windowID, processID: pid,
                title: String(title.prefix(512)), previewFrame: frame
            ))
        }

        guard !labels.isEmpty else {
            releaseWindowLabels()
            return
        }
        if isEntering {
            let frames = Dictionary(uniqueKeysWithValues: labels.map { ($0.windowID, $0.previewFrame) })
            if frames != settlingLabelFrames {
                settlingLabelFrames = frames
                labelLayoutStableSince = CACurrentMediaTime()
            } else if let since = labelLayoutStableSince, CACurrentMediaTime() - since >= 0.2 {
                finishWindowLabelEntry()
            }
        } else if needsStableLabelLayout {
            // Space/gesture/drag transitions retain the original 200ms gate.
            let frames = Dictionary(uniqueKeysWithValues: labels.map { ($0.windowID, $0.previewFrame) })
            let now = CACurrentMediaTime()
            guard frames == settlingLabelFrames else {
                settlingLabelFrames = frames
                labelLayoutStableSince = now
                return
            }
            guard let since = labelLayoutStableSince, now - since >= 0.2 else { return }
            needsStableLabelLayout = false
            settlingLabelFrames.removeAll(keepingCapacity: false)
            labelLayoutStableSince = nil
            clearWindowLabelEntryScheduling()
        }
        let oldCount = visibleWindowLabelCount
        if labelsOverlay == nil {
            labelsOverlay = MissionControlLabelsOverlay()
        }
        autoreleasepool {
            labelsOverlay?.show(
                labels, style: windowLabelStyle,
                cursorLocation: CGEvent(source: nil).map { labelHoverLocation(at: $0.location) }
            )
        }
        if oldCount != visibleWindowLabelCount {
            AppLogger.missionControl.info("Window labels refreshed: \(labels.count, privacy: .public) previews")
        }
    }

    private func windowLabelTitle(
        windowID: CGWindowID, processID: pid_t, info: [String: Any],
        isEntering: Bool, titlesByProcess: inout [pid_t: [CGWindowID: String]]
    ) -> String {
        var title = info[kCGWindowName as String] as? String ?? ""
        if isEntering, title.isEmpty {
            title = labelsOverlay?.cachedTitle(for: windowID, processID: processID) ?? ""
        }
        if title.isEmpty {
            if titlesByProcess[processID] == nil {
                titlesByProcess[processID] = accessibilityService.windowTitles(for: processID)
            }
            title = titlesByProcess[processID]?[windowID] ?? ""
        }
        if title.isEmpty {
            title = info[kCGWindowOwnerName as String] as? String ?? ""
        }
        return title
    }

    func releaseWindowLabels() {
        labelDisplaySpaces = [:]
        guard labelsOverlay != nil else { return }
        autoreleasepool {
            labelsOverlay?.invalidate()
            labelsOverlay = nil
        }
    }

    func setupWindowLabelObservers() {
        labelsPurgeObserver = NotificationCenter.default.addObserver(
            forName: .mcscPurgeCaches, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseWindowLabels() }
        }
        labelsScreenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.releaseWindowLabels()
                self?.beginSpaceTransition()
            }
        }
    }

    func removeWindowLabelObservers() {
        if let observer = labelsPurgeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = labelsScreenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        labelsPurgeObserver = nil
        labelsScreenObserver = nil
    }
}
