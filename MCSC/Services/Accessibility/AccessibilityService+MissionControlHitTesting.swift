import ApplicationServices
import Cocoa

extension AccessibilityService {
    func missionControlSpace(at point: CGPoint) -> Int? {
        guard let screen = NSScreen.screens.first(where: { ScreenGeometry.axBounds(for: $0).contains(point) }),
              let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        return SpaceManagementService().activeDisplaySpaces()[display.uint32Value]
    }

    func matchesMissionControlPreview(
        _ preview: (tileElement: AXUIElement, windowID: CGWindowID),
        at point: CGPoint, matchingWindowIDs: Set<CGWindowID>?, spaceID: Int?
    ) -> Bool {
        guard matchingWindowIDs?.contains(preview.windowID) != false,
              let frame = getFrame(for: preview.tileElement),
              !frame.isEmpty, !frame.isInfinite, !frame.isNull, frame.contains(point) else { return false }
        guard matchingWindowIDs != nil else { return true }
        let identifier: String? = getAttributeValue(kAXIdentifierAttribute, for: preview.tileElement)
        guard let identifier, let range = identifier.range(of: ".space.", options: .backwards) else { return true }
        guard let tileSpace = Int(identifier[range.upperBound...]), let spaceID else { return false }
        return tileSpace == spaceID
    }
}
