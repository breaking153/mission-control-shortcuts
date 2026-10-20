import CoreGraphics

enum MissionControlWindowButton: Int, CaseIterable {
    case close, minimize, fullscreen
}

/// Visible symbols sit inside larger, adjacent hit cells with no dead gaps.
struct MissionControlWindowButtonLayout {
    let scale: CGFloat

    init(scale: CGFloat) {
        self.scale = scale.isFinite ? min(max(scale, 0.75), 2) : 1.25
    }

    var hitSide: CGFloat {
        40 * scale
    }

    var size: CGSize {
        CGSize(width: hitSide * 3, height: hitSide)
    }

    func hitFrame(for button: MissionControlWindowButton) -> CGRect {
        CGRect(x: CGFloat(button.rawValue) * hitSide, y: 0, width: hitSide, height: hitSide)
    }

    func visualFrame(for button: MissionControlWindowButton) -> CGRect {
        hitFrame(for: button).insetBy(dx: 4 * scale, dy: 4 * scale)
    }

    func button(at point: CGPoint) -> MissionControlWindowButton? {
        MissionControlWindowButton.allCases.first { hitFrame(for: $0).contains(point) }
    }

    func panelFrame(anchor: CGPoint, screen: CGRect) -> CGRect {
        CGRect(
            x: min(max(anchor.x - hitSide / 2, screen.minX + 2), screen.maxX - size.width - 2),
            y: min(max(anchor.y - hitSide / 2, screen.minY + 2), screen.maxY - size.height - 2),
            width: size.width, height: size.height
        )
    }
}
