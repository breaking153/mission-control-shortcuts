import Cocoa
import ObjectiveC

extension SpaceManagementServiceProtocol {
    func managedSpaces(on _: CGDirectDisplayID) -> [MissionControlSpace] {
        []
    }

    func moveWindow(_: CGWindowID, processID _: pid_t, to _: Int, on _: CGDirectDisplayID) -> Bool {
        false
    }
}

extension SpaceManagementService {
    func managedSpaces(on displayID: CGDirectDisplayID) -> [MissionControlSpace] {
        guard let displays = Self.CGSCopyManagedDisplaySpaces(Self.CGSMainConnectionID()) as? [[String: Any]]
        else { return [] }
        let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        let identifier = uuid.map { CFUUIDCreateString(kCFAllocatorDefault, $0) as String }
        let display = displays.first {
            guard let name = $0["Display Identifier"] as? String else { return false }
            return name.caseInsensitiveCompare(identifier ?? "") == .orderedSame
                || (name.uppercased() == "MAIN" && displayID == CGMainDisplayID())
        } ?? (displays.count == 1 ? displays.first : nil)
        guard let spaces = display?["Spaces"] as? [[String: Any]] else { return [] }
        return spaces.compactMap { space in
            guard let id = space["ManagedSpaceID"] as? Int, let type = space["type"] as? Int else { return nil }
            let layout = space["TileLayoutManager"] as? [String: Any]
            let tiles = layout?["TileSpaces"] as? [[String: Any]] ?? []
            // Split View is a group, not a single-window fullscreen drag.
            let single = type == 4 && tiles.count <= 1
            return MissionControlSpace(
                id: id, displayID: displayID, type: type,
                windowID: single ? (space["fs_wid"] as? NSNumber)?.uint32Value : nil,
                processID: single ? (space["pid"] as? NSNumber)?.int32Value : nil
            )
        }
    }

    /// The legacy move API silently does nothing on current macOS. Invoke the
    /// narrow runtime bridge, without retaining an operation or new framework.
    func moveWindow(_ windowID: CGWindowID, processID: pid_t, to spaceID: Int,
                    on displayID: CGDirectDisplayID) -> Bool {
        guard managedSpaces(on: displayID).contains(where: { $0.id == spaceID && $0.type == 0 }),
              let app = NSRunningApplication(processIdentifier: processID), app.isSafeTargetProcess,
              let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
              info.contains(where: {
                  ($0[kCGWindowNumber as String] as? CGWindowID) == windowID
                      && ($0[kCGWindowOwnerPID as String] as? pid_t) == processID
              }),
              let operationClass = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation")
        else { return false }
        let allocSelector = NSSelectorFromString("alloc")
        let initSelector = NSSelectorFromString("initWithWindows:spaceID:")
        let performSelector = NSSelectorFromString("performWithWMBridgeDelegate")
        guard let allocateMethod = class_getClassMethod(operationClass, allocSelector),
              let initializeMethod = class_getInstanceMethod(operationClass, initSelector),
              let performMethod = class_getInstanceMethod(operationClass, performSelector) else {
            AppLogger.missionControl.error("Fullscreen Space move bridge is unavailable")
            return false
        }
        typealias Allocate = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>
        typealias Initialize = @convention(c) (AnyObject, Selector, NSArray, UInt64) -> Unmanaged<AnyObject>?
        typealias Perform = @convention(c) (AnyObject, Selector) -> Void
        let allocate = unsafeBitCast(method_getImplementation(allocateMethod), to: Allocate.self)
        let initialize = unsafeBitCast(method_getImplementation(initializeMethod), to: Initialize.self)
        let perform = unsafeBitCast(method_getImplementation(performMethod), to: Perform.self)
        let allocation = allocate(operationClass, allocSelector)
        // init consumes alloc's +1; ARC takes that same ownership exactly once.
        guard let operation = initialize(
            allocation.takeUnretainedValue(), initSelector, [NSNumber(value: windowID)], UInt64(spaceID)
        )?.takeRetainedValue() else { return false }
        perform(operation, performSelector)
        return true
    }
}
