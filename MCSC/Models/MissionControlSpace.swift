import CoreGraphics
import Foundation

/// A Space in native display order, without retained Accessibility objects.
struct MissionControlSpace {
    let id: Int
    let displayID: CGDirectDisplayID
    let type: Int
    let windowID: CGWindowID?
    let processID: pid_t?
}

struct MissionControlFullscreenDrag {
    let space: MissionControlSpace
    let startedAt: TimeInterval
    let startPoint: CGPoint
    var hasDragged = false
    var destinationSpaceID: Int?
    var destinationDisplayID: CGDirectDisplayID?
    var moveRequested = false
}
