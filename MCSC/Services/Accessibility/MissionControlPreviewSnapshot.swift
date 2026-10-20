import ApplicationServices
import Cocoa

/// Bounded, session-only AX enumeration. Original CG window bounds are never
/// used as a substitute for Mission Control's scaled preview geometry.
enum MissionControlPreviewSnapshot {
    private struct Candidate {
        let element: AXUIElement
        let windowID: CGWindowID
        let frame: CGRect
        let spaceID: Int?
        let hasSpaceIdentifier: Bool
    }

    static func collect(
        roots: [AXUIElement],
        matchingWindowIDs: Set<CGWindowID>,
        accessibility: AccessibilityServiceProtocol
    ) -> [MissionControlPreview] {
        var previews: [MissionControlPreview] = []
        enumerate(roots: roots, matchingWindowIDs: matchingWindowIDs, accessibility: accessibility) { candidate in
            previews.append(MissionControlPreview(
                windowID: candidate.windowID, frame: candidate.frame, spaceID: candidate.spaceID
            ))
        }
        return previews
    }

    /// WindowManager's direct AX hit test can return an inactive desktop's
    /// replica. Resolve the smallest matching tile from current AX geometry.
    static func find(
        at point: CGPoint,
        spaceID: Int,
        roots: [AXUIElement],
        matchingWindowIDs: Set<CGWindowID>,
        accessibility: AccessibilityServiceProtocol
    ) -> (tileElement: AXUIElement, windowID: CGWindowID)? {
        var best: (element: AXUIElement, windowID: CGWindowID, area: CGFloat)?
        var isAmbiguous = false
        let didComplete = enumerate(
            roots: roots, matchingWindowIDs: matchingWindowIDs, accessibility: accessibility
        ) { candidate in
            guard candidate.frame.contains(point),
                  !candidate.hasSpaceIdentifier || candidate.spaceID == spaceID else { return }
            let area = candidate.frame.width * candidate.frame.height
            guard area.isFinite, area > 0 else { return }
            if let best {
                if area > best.area {
                    return
                }
                if area == best.area {
                    // Dock and WindowManager can expose the same tile. Only
                    // equally sized candidates for different windows conflict.
                    if candidate.windowID != best.windowID {
                        isAmbiguous = true
                    }
                    return
                }
            }
            best = (candidate.element, candidate.windowID, area)
            isAmbiguous = false
        }
        guard didComplete, let best, !isAmbiguous else { return nil }
        return (best.element, best.windowID)
    }

    @discardableResult
    private static func enumerate(
        roots: [AXUIElement],
        matchingWindowIDs: Set<CGWindowID>,
        accessibility: AccessibilityServiceProtocol,
        visit: (Candidate) -> Void
    ) -> Bool {
        var didComplete = true
        var remaining = 1024
        var pending = roots.reversed().map { (element: $0, depth: 0) }

        while remaining > 0, let item = pending.popLast() {
            remaining -= 1
            let hidden: Bool? = accessibility.getAttributeValue("AXHidden", for: item.element)
            if hidden == true {
                continue
            }

            let number: NSNumber? = accessibility.getAttributeValue("wid", for: item.element)
            if let number {
                let windowID = number.uint32Value
                let role: String? = accessibility.getAttributeValue(kAXRoleAttribute, for: item.element)
                if role == kAXButtonRole, matchingWindowIDs.contains(windowID),
                   let frame = accessibility.getFrame(for: item.element),
                   !frame.isEmpty, !frame.isInfinite, !frame.isNull,
                   NSScreen.screens.contains(where: { ScreenGeometry.axBounds(for: $0).contains(
                       CGPoint(x: frame.midX, y: frame.midY)
                   ) }) {
                    let identifier: String? = accessibility.getAttributeValue(kAXIdentifierAttribute, for: item.element)
                    let spaceRange = identifier?.range(of: ".space.", options: .backwards)
                    let spaceID = spaceRange.flatMap { range in
                        identifier.flatMap { Int($0[range.upperBound...]) }
                    }
                    visit(Candidate(
                        element: item.element, windowID: windowID, frame: frame,
                        spaceID: spaceID, hasSpaceIdentifier: spaceRange != nil
                    ))
                    // Only a matched preview is terminal; containers can also
                    // expose their own window ID and still have preview children.
                    continue
                }
            }

            var children: CFArray?
            var attribute = kAXVisibleChildrenAttribute as CFString
            var count = 0
            if AXUIElementGetAttributeValueCount(item.element, attribute, &count) != .success {
                attribute = kAXChildrenAttribute as CFString
                let result = AXUIElementGetAttributeValueCount(item.element, attribute, &count)
                if result != .success {
                    // Leaf elements commonly omit AXChildren entirely.
                    if result != .attributeUnsupported, result != .noValue {
                        didComplete = false
                    }
                    continue
                }
            }
            guard count >= 0 else {
                didComplete = false
                continue
            }
            guard count > 0 else { continue }
            guard item.depth < 10 else {
                didComplete = false
                continue
            }
            let limit = min(count, remaining - pending.count)
            if limit < count {
                didComplete = false
            }
            guard limit > 0 else { continue }
            guard AXUIElementCopyAttributeValues(
                item.element, attribute, 0, limit, &children
            ) == .success, let children = children as? [AXUIElement] else {
                didComplete = false
                continue
            }
            if children.count != limit {
                didComplete = false
            }
            pending.append(contentsOf: children.reversed().map { ($0, item.depth + 1) })
        }
        return didComplete && pending.isEmpty
    }
}
