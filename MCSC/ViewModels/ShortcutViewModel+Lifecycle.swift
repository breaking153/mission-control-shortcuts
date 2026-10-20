import Cocoa

/// Service lifecycle gating for `ShortcutViewModel`: which heavyweight
/// services run is derived from the feature toggles, and every `start()` /
/// `stop()` pair is idempotent. Split from the main file to stay under the
/// SwiftLint `file_length` budget.
@MainActor
extension ShortcutViewModel {
    func syncNativeWindowButtonHitService() {
        if config.isNativeWindowButtonHitExpansionEnabled, nativeWindowButtonHitService == nil {
            nativeWindowButtonHitService = NativeWindowButtonHitService(
                accessibilityService: accessibilityService,
                isMissionControlActiveProvider: { [weak self] in
                    self?.missionControlService.checkMissionControlActive(force: true) ?? false
                }
            )
        }
        nativeWindowButtonHitService?.isEnabled = config.isNativeWindowButtonHitExpansionEnabled
        nativeWindowButtonHitService?.scale = CGFloat(config.nativeWindowButtonHitScale)
    }

    /// `true` when any feature that consumes trackpad frames is enabled.
    /// When `false`, `MultitouchService` is not started — avoiding dlopen
    /// of MultitouchSupport.framework and its 60-120 Hz frame stream.
    var needsMultitouch: Bool {
        config.isGesturesEnabled || (config.isMissionControlLabelsEnabled && hoverService.isMissionControlActive)
    }

    /// `true` when the dock interaction suppressor should be active.
    var needsDockSuppressor: Bool {
        config.isGesturesEnabled && config.isDockActionsOutsideMCEnabled
    }

    var needsMissionControlTracking: Bool {
        isHoverCloseButtonEnabled || config.isMissionControlLabelsEnabled
    }

    /// Labels need system gesture frames only while Mission Control is open.
    /// Do not restart an already listening trackpad on overview transitions.
    func syncMultitouchLifecycle(forceRestart: Bool = false) {
        if needsMultitouch {
            if forceRestart || !multitouchService.isListening {
                multitouchService.start()
            }
        } else {
            if hadThreeOrMoreTouches {
                hadThreeOrMoreTouches = false
                hoverService.setOverviewGestureInProgress(false)
            }
            multitouchService.stop()
            gestureEngine.reset()
        }
    }

    /// Starts or stops heavyweight services in response to toggle changes.
    func syncServiceLifecycles() {
        if needsMissionControlTracking {
            hoverService.start()
        } else {
            hoverService.stop()
        }

        syncMultitouchLifecycle()

        if needsDockSuppressor {
            dockSuppressor.start()
        } else {
            dockSuppressor.stop()
        }
    }
}
