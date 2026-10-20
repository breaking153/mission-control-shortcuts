import CoreGraphics

/// Screen-space geometry only; expanding a button never extends outside its window.
enum NativeWindowButtonHitGeometry {
    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return 1.6 }
        return min(3, max(1, scale))
    }

    static func expandedFrame(button: CGRect, window: CGRect, scale: CGFloat) -> CGRect? {
        guard isValid(button), isValid(window), window.contains(button),
              button.width <= 32, button.height <= 32 else { return nil }
        let scale = clampedScale(scale)
        let expanded = button.insetBy(
            dx: -button.width * (scale - 1) / 2,
            dy: -button.height * (scale - 1) / 2
        ).intersection(window)
        return isValid(expanded) ? expanded : nil
    }

    static func squaredDistance(from point: CGPoint, toCenterOf frame: CGRect) -> CGFloat {
        let dx = point.x - frame.midX
        let dy = point.y - frame.midY
        return dx * dx + dy * dy
    }

    private static func isValid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite &&
            frame.width.isFinite && frame.height.isFinite &&
            frame.width > 0 && frame.height > 0
    }
}
