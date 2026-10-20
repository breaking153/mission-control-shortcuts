import ApplicationServices
import Cocoa
import Darwin

/// Adds bounded, invisible click margins to native traffic lights using the existing event tap.
/// AX elements are resolved only on mouse-down and retained for one physical press at most.
@MainActor
final class NativeWindowButtonHitService {
    var isEnabled = false {
        didSet {
            if !isEnabled {
                cancelPendingPress()
            }
        }
    }

    var scale: CGFloat = 1.6 {
        didSet {
            scale = NativeWindowButtonHitGeometry.clampedScale(scale)
            cancelPendingPress()
        }
    }

    private struct PendingPress {
        var button: AXUIElement?
        weak var localWindow: NSWindow?
        weak var localButton: NSButton?
        var localButtonType: NSWindow.ButtonType?
        let expandedFrame: CGRect
        let attribute: String
    }

    private let accessibilityService: AccessibilityServiceProtocol
    private let isMissionControlActiveProvider: () -> Bool
    private var pendingPress: PendingPress?
    private var cancellationGeneration: UInt = 0

    init(
        accessibilityService: AccessibilityServiceProtocol,
        isMissionControlActiveProvider: @escaping () -> Bool
    ) {
        self.accessibilityService = accessibilityService
        self.isMissionControlActiveProvider = isMissionControlActiveProvider
    }

    /// Returns true only for a margin press already owned by this service.
    func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .leftMouseDown:
            // A new down also recovers from a release lost while the tap was disabled.
            pendingPress = nil
            let generation = cancellationGeneration
            guard isEnabled, scale > 1, !hasActionModifiers(event),
                  !isMissionControlActiveProvider(), generation == cancellationGeneration,
                  isEnabled, scale > 1,
                  let press = resolvePress(at: event.location) else { return false }
            pendingPress = press
            AppLogger.accessibility.debug("Native window button margin armed: \(press.attribute, privacy: .public)")
            return true

        case .leftMouseDragged:
            guard let press = pendingPress else { return false }
            if !isEnabled || isMissionControlActiveProvider() || hasActionModifiers(event) ||
                !press.expandedFrame.contains(event.location) {
                cancelPendingPress()
            }
            return true

        case .leftMouseUp:
            guard let press = pendingPress else { return false }
            pendingPress = nil
            let generation = cancellationGeneration
            guard isEnabled, !isMissionControlActiveProvider(), generation == cancellationGeneration,
                  isEnabled, !hasActionModifiers(event),
                  press.expandedFrame.contains(event.location) else { return true }
            let accepted: Bool
            if let button = press.button {
                guard let enabled: Bool = accessibilityService.getAttributeValue(kAXEnabledAttribute, for: button),
                      enabled else { return true }
                accepted = accessibilityService.performAction(kAXPressAction, on: button)
            } else if let window = press.localWindow, let button = press.localButton,
                      let type = press.localButtonType,
                      window.isVisible, !window.isMiniaturized, button.window === window,
                      window.standardWindowButton(type) === button,
                      button.isEnabled, !button.isHiddenOrHasHiddenAncestor {
                button.performClick(nil)
                accepted = true
            } else {
                return true
            }
            AppLogger.accessibility.debug(
                "Native window button margin action: \(press.attribute, privacy: .public), accepted: \(accepted, privacy: .public)"
            )
            return true

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            cancelPendingPress()
            return false

        default:
            return false
        }
    }

    /// Keep the matching release swallowed after cancelling an already swallowed down.
    /// The coordinator also calls this when Mission Control opens between mouse events.
    func cancelPendingPress() {
        cancellationGeneration &+= 1
        pendingPress?.button = nil
        pendingPress?.localWindow = nil
        pendingPress?.localButton = nil
    }

    func stop() {
        isEnabled = false
        cancelPendingPress()
    }

    private func resolvePress(at point: CGPoint) -> PendingPress? {
        guard point.x.isFinite, point.y.isFinite else { return nil }

        // Resolve our own title bars locally. AX requests against this process can wait
        // on the same main thread that is handling the event-tap callback.
        if let application = NSApp {
            let cocoaPoint = ScreenGeometry.cocoaPoint(for: point)
            let number = NSWindow.windowNumber(at: cocoaPoint, belowWindowWithWindowNumber: 0)
            if let window = application.window(withWindowNumber: number) {
                return resolveLocalPress(at: point, in: window)
            }
        }
        guard let hit = accessibilityService.getElement(at: point) else { return nil }

        // Querying our own AX window from the event-tap main thread can wait on this thread.
        var ownerPID: pid_t = 0
        guard AXUIElementGetPid(hit, &ownerPID) == .success, ownerPID != getpid(),
              let window = accessibilityService.getWindow(for: hit),
              let windowRole: String = accessibilityService.getAttributeValue(kAXRoleAttribute, for: window),
              windowRole == kAXWindowRole,
              let windowFrame = accessibilityService.getFrame(for: window),
              windowFrame.contains(point),
              // Standard traffic lights live in the title-bar band. Avoid probing every
              // button for ordinary content clicks and reject controls deep in a window.
              point.y - windowFrame.minY <= 64 else { return nil }

        // An actual control under the pointer keeps its own click, including custom toolbar buttons.
        let hitRole: String? = accessibilityService.getAttributeValue(kAXRoleAttribute, for: hit)
        guard hitRole == kAXWindowRole || hitRole == kAXGroupRole || hitRole == kAXToolbarRole else {
            return nil
        }

        var nearest: PendingPress?
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for attribute in [kAXCloseButtonAttribute, kAXMinimizeButtonAttribute,
                          kAXFullScreenButtonAttribute, kAXZoomButtonAttribute] {
            guard let button: AXUIElement = accessibilityService.getAttributeValue(attribute, for: window),
                  let frame = accessibilityService.getFrame(for: button) else { continue }

            // Never replace a direct physical click, even when a neighboring margin overlaps it.
            if frame.contains(point) {
                return nil
            }

            guard frame.maxY - windowFrame.minY <= 64,
                  let expanded = NativeWindowButtonHitGeometry.expandedFrame(
                      button: frame, window: windowFrame, scale: scale
                  ), expanded.contains(point),
                  let role: String = accessibilityService.getAttributeValue(kAXRoleAttribute, for: button),
                  role == kAXButtonRole,
                  let subrole: String = accessibilityService.getAttributeValue(kAXSubroleAttribute, for: button),
                  isNativeSubrole(subrole, for: attribute),
                  let enabled: Bool = accessibilityService.getAttributeValue(kAXEnabledAttribute, for: button),
                  enabled,
                  let ownerWindow = accessibilityService.getWindow(for: button),
                  CFEqual(ownerWindow, window) else { continue }

            let distance = NativeWindowButtonHitGeometry.squaredDistance(from: point, toCenterOf: frame)
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = PendingPress(button: button, expandedFrame: expanded, attribute: attribute)
            }
        }
        return nearest
    }

    private func resolveLocalPress(at point: CGPoint, in window: NSWindow) -> PendingPress? {
        guard window.isVisible, !window.isMiniaturized, !window.ignoresMouseEvents else { return nil }
        let windowFrame = quartzFrame(window.frame)
        guard windowFrame.contains(point), point.y - windowFrame.minY <= 64 else { return nil }

        // Preserve other controls that occupy a native title-bar margin.
        if let contentView = window.contentView {
            let frameView = contentView.superview ?? contentView
            let cocoaPoint = ScreenGeometry.cocoaPoint(for: point)
            let pointInWindow = window.convertPoint(fromScreen: cocoaPoint)
            let pointInFrame = frameView.convert(pointInWindow, from: nil)
            var hit = frameView.hitTest(pointInFrame)
            var depth = 0
            while let view = hit, depth < 16 {
                if view is NSControl {
                    return nil
                }
                if view === frameView {
                    break
                }
                hit = view.superview
                depth += 1
            }
        }

        var nearest: PendingPress?
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type),
                  button.window === window, !button.isHiddenOrHasHiddenAncestor else { continue }
            let frame = quartzFrame(window.convertToScreen(button.convert(button.bounds, to: nil)))
            if frame.contains(point) {
                return nil
            }
            guard button.isEnabled, frame.maxY - windowFrame.minY <= 64,
                  let expanded = NativeWindowButtonHitGeometry.expandedFrame(
                      button: frame, window: windowFrame, scale: scale
                  ), expanded.contains(point) else { continue }
            let distance = NativeWindowButtonHitGeometry.squaredDistance(from: point, toCenterOf: frame)
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = PendingPress(
                    button: nil, localWindow: window, localButton: button, localButtonType: type,
                    expandedFrame: expanded, attribute: localAttribute(for: type)
                )
            }
        }
        return nearest
    }

    private func quartzFrame(_ cocoaFrame: CGRect) -> CGRect {
        CGRect(x: cocoaFrame.minX, y: ScreenGeometry.primaryScreenHeight - cocoaFrame.maxY,
               width: cocoaFrame.width, height: cocoaFrame.height)
    }

    private func localAttribute(for type: NSWindow.ButtonType) -> String {
        switch type {
        case .closeButton: kAXCloseButtonAttribute
        case .miniaturizeButton: kAXMinimizeButtonAttribute
        default: kAXZoomButtonAttribute
        }
    }

    private func isNativeSubrole(_ subrole: String, for attribute: String) -> Bool {
        switch attribute {
        case kAXCloseButtonAttribute: subrole == kAXCloseButtonSubrole
        case kAXMinimizeButtonAttribute: subrole == kAXMinimizeButtonSubrole
        case kAXZoomButtonAttribute: subrole == kAXZoomButtonSubrole
        case kAXFullScreenButtonAttribute: subrole == kAXFullScreenButtonSubrole
        default: false
        }
    }

    private func hasActionModifiers(_ event: CGEvent) -> Bool {
        !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
    }
}
