import Cocoa

/// Small, mouse-transparent panels; no full-screen backing surface, blur,
/// animations, or per-label view hierarchy. All resources are session scoped.
@MainActor
final class MissionControlLabelsOverlay: FloatingOverlayProtocol {
    private struct Entry {
        let panel: NSPanel
        let view: WindowLabelView
        var label: MissionControlWindowLabel
        var titleWidth: CGFloat
    }

    private var entries: [CGWindowID: Entry] = [:]
    private var icons: [pid_t: NSImage] = [:]
    private var style = MissionControlLabelStyle()
    private var hoverLocation: CGPoint?
    private var draggedWindowID: CGWindowID?
    var isVisible: Bool {
        entries.values.contains { $0.panel.isVisible }
    }

    var visibleLabelCount: Int {
        entries.values.reduce(0) { $0 + ($1.panel.isVisible ? 1 : 0) }
    }

    func show(
        _ labels: [MissionControlWindowLabel], style: MissionControlLabelStyle,
        cursorLocation: CGPoint? = nil
    ) {
        let style = style.validated
        let hoverLocation = cursorLocation ?? self.hoverLocation
        if self.style != style {
            hide()
            self.style = style
        }
        self.hoverLocation = hoverLocation
        let windowIDs = Set(labels.map(\.windowID))
        for windowID in entries.keys.filter({ !windowIDs.contains($0) }) {
            entries.removeValue(forKey: windowID)?.panel.close()
        }
        let processIDs = Set(labels.map(\.processID))
        icons = icons.filter { processIDs.contains($0.key) }

        for label in labels {
            if let entry = entries[label.windowID], entry.label == label {
                continue
            }
            guard let screen = NSScreen.screens.first(where: {
                ScreenGeometry.axBounds(for: $0).contains(CGPoint(
                    x: label.previewFrame.midX,
                    y: label.previewFrame.midY
                ))
            }) else { continue }
            let font = NSFont.systemFont(ofSize: style.fontSize, weight: .regular)
            let textWidth: CGFloat = if let entry = entries[label.windowID], entry.label.title == label.title {
                entry.titleWidth
            } else {
                (label.title as NSString).size(withAttributes: [.font: font]).width
            }
            let layout = MissionControlLabelLayout(
                preview: label.previewFrame, screen: ScreenGeometry.axBounds(for: screen),
                titleWidth: textWidth, style: style
            )
            let frame = NSRect(
                x: layout.panelFrame.minX,
                y: ScreenGeometry.primaryScreenHeight - layout.panelFrame.maxY,
                width: layout.panelFrame.width, height: layout.panelFrame.height
            )
            if var entry = entries[label.windowID] {
                let needsRedraw = entry.label.title != label.title || entry.label.processID != label.processID
                    || entry.view.layout?.iconFrame != layout.iconFrame || entry.view.layout?.titleFrame != layout
                    .titleFrame
                entry.view.title = label.title
                entry.view.icon = icon(for: label.processID)
                entry.view.layout = layout
                entry.view.font = font
                entry.view.setAccessibilityLabel(label.title)
                if needsRedraw {
                    entry.view.needsDisplay = true
                }
                entry.panel.setFrame(frame, display: needsRedraw)
                entry.label = label
                entry.titleWidth = textWidth
                entries[label.windowID] = entry
            } else {
                let panel = OverlayPanelFactory.createPanel(
                    contentRect: frame, ignoresMouseEvents: true
                )
                panel.animationBehavior = .none
                let view = WindowLabelView(frame: NSRect(origin: .zero, size: frame.size))
                view.title = label.title
                view.icon = icon(for: label.processID)
                view.layout = layout
                view.font = font
                view.autoresizingMask = [.width, .height]
                view.setAccessibilityElement(true)
                view.setAccessibilityRole(.staticText)
                view.setAccessibilityLabel(label.title)
                view.setAccessibilityIdentifier("mcsc.windowLabel.\(label.windowID)")
                panel.contentView = view
                entries[label.windowID] = Entry(panel: panel, view: view, label: label, titleWidth: textWidth)
            }
        }
        applyHoverVisibility()
    }

    func updateHover(at point: CGPoint) {
        hoverLocation = point
        applyHoverVisibility()
    }

    func containsPreview(at point: CGPoint) -> Bool {
        entries.values.contains { $0.label.previewFrame.contains(point) }
    }

    func windowID(at point: CGPoint) -> CGWindowID? {
        var bestID: CGWindowID?
        var bestArea = CGFloat.infinity
        for entry in entries.values where entry.label.previewFrame.contains(point) {
            let area = entry.label.previewFrame.width * entry.label.previewFrame.height
            if area < bestArea || (area == bestArea && entry.label.windowID < (bestID ?? .max)) {
                bestID = entry.label.windowID
                bestArea = area
            }
        }
        return bestID
    }

    func setDraggedWindowID(_ windowID: CGWindowID?) {
        draggedWindowID = windowID
        applyHoverVisibility()
    }

    func cachedTitle(for windowID: CGWindowID, processID: pid_t) -> String? {
        guard let entry = entries[windowID], entry.label.processID == processID else { return nil }
        return entry.label.title
    }

    func hide() {
        for entry in entries.values {
            entry.panel.orderOut(nil)
        }
        for entry in entries.values {
            entry.panel.close()
        }
        entries.removeAll(keepingCapacity: false)
        icons.removeAll(keepingCapacity: false)
        hoverLocation = nil
        draggedWindowID = nil
    }

    func invalidate() {
        hide()
    }

    private func applyHoverVisibility() {
        // Mission Control can briefly overlap previews while rearranging them.
        // Prefer the smallest hit, with a stable tie break, so only one label hides.
        let hoveredWindowID = draggedWindowID ?? hoverLocation.flatMap { windowID(at: $0) }
        for entry in entries.values {
            if entry.label.windowID == hoveredWindowID {
                if entry.panel.isVisible {
                    entry.panel.orderOut(nil)
                }
            } else if !entry.panel.isVisible {
                entry.panel.orderFrontRegardless()
            }
        }
    }

    private func icon(for pid: pid_t) -> NSImage? {
        if let cached = icons[pid] {
            return cached
        }
        // Rasterize one small icon per application, rather than keeping its
        // potentially 1024px NSRunningApplication icon alive for each window.
        let icon: NSImage? = autoreleasepool {
            let size = style.iconSize
            let pixels = Int(ceil(size * 2))
            guard let source = NSRunningApplication(processIdentifier: pid)?.icon,
                  let bitmap = NSBitmapImageRep(
                      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                      isPlanar: false, colorSpaceName: .deviceRGB,
                      bytesPerRow: 0, bitsPerPixel: 0
                  ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
            bitmap.size = NSSize(width: size, height: size)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: 2, y: 2)
            source.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
            NSGraphicsContext.restoreGraphicsState()
            let image = NSImage(size: bitmap.size)
            image.addRepresentation(bitmap)
            return image
        }
        if let icon {
            icons[pid] = icon
        }
        return icon
    }
}

@MainActor
private final class WindowLabelView: NSView {
    var font = NSFont.systemFont(ofSize: 13, weight: .regular)
    var layout: MissionControlLabelLayout?
    var title = ""
    var icon: NSImage?

    override func draw(_: NSRect) {
        guard let layout else { return }
        icon?.draw(in: layout.iconFrame)
        let pill = layout.titleFrame
        NSColor(white: 0.12, alpha: 0.86).setFill()
        let path = NSBezierPath(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        path.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 0.5
        path.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingMiddle
        (title as NSString).draw(
            in: pill.insetBy(dx: min(10, pill.width / 4), dy: 4),
            withAttributes: [.font: font, .foregroundColor: NSColor.white, .paragraphStyle: paragraph]
        )
    }
}
