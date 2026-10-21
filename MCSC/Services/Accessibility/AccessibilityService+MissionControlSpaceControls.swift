import ApplicationServices
import Cocoa

extension AccessibilityServiceProtocol {
    func getMissionControlSpaceButtonIndex(at _: CGPoint) -> Int? {
        nil
    }
}

extension AccessibilityService {
    /// Space tiles have no window ID; their AX order matches managed Spaces.
    func getMissionControlSpaceButtonIndex(at point: CGPoint) -> Int? {
        guard let root = getWindowManagerAXElement() else { return nil }
        var hit: AXUIElement?
        _ = AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &hit)
        var ancestors: [AXUIElement] = []
        var current = hit
        for _ in 0 ..< 8 {
            guard let element = current else { break }
            ancestors.append(element)
            current = getAttributeValue(kAXParentAttribute, for: element)
        }
        var pending = [root]
        var remaining = 128
        while let element = pending.popLast(), remaining > 0 {
            remaining -= 1
            let identifier: String? = getAttributeValue(kAXIdentifierAttribute, for: element)
            if identifier == "mc.spaces.list" {
                let children: [AXUIElement] = getAttributeValue(kAXChildrenAttribute, for: element) ?? []
                let buttons = children.filter {
                    let role: String? = getAttributeValue(kAXRoleAttribute, for: $0)
                    let identifier: String? = getAttributeValue(kAXIdentifierAttribute, for: $0)
                    return role == kAXButtonRole && identifier != "mc.spaces.add"
                }
                if let index = buttons.firstIndex(where: { button in ancestors.contains { CFEqual($0, button) } }) {
                    return index
                }
                // Native Space tiles expose their centre as AXPosition.
                let matches = buttons.enumerated().compactMap { index, button -> (Int, CGFloat)? in
                    guard let frame = getFrame(for: button) else { return nil }
                    let bounds = frame.offsetBy(dx: -frame.width / 2, dy: -frame.height / 2)
                    guard bounds.contains(point) else { return nil }
                    return (index, hypot(point.x - frame.minX, point.y - frame.minY))
                }
                if let match = matches.min(by: { $0.1 < $1.1 }) {
                    return match.0
                }
            }
            let children: [AXUIElement] = getAttributeValue(kAXChildrenAttribute, for: element) ?? []
            pending.append(contentsOf: children.prefix(max(0, remaining - pending.count)))
        }
        return nil
    }
}
