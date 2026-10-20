import CoreGraphics

/// Panel geometry is in Quartz coordinates; drawing rectangles are local
/// Cocoa coordinates. No AX, service, application, or view state is retained.
struct MissionControlLabelLayout {
    let panelFrame: CGRect
    let iconFrame: CGRect
    let titleFrame: CGRect

    init(preview: CGRect, screen: CGRect, titleWidth: CGFloat, style: MissionControlLabelStyle) {
        let style = style.validated
        let titleHeight = ceil(style.fontSize * 1.3) + 8
        let gap: CGFloat = 6
        let maxWidth = max(32, min(320, preview.width - 12, screen.width - 12))
        let vertical = style.iconPosition == .above || style.iconPosition == .below
        let icon = min(style.iconSize, vertical ? maxWidth : maxWidth - gap - 16)
        let textWidth = max(16, min(titleWidth + 20, maxWidth - (vertical ? 0 : icon + gap)))
        let width = vertical ? max(icon, textWidth) : icon + gap + textWidth
        let height = vertical ? icon + gap + titleHeight : max(icon, titleHeight)

        let y: CGFloat = switch style.position {
        case .top: preview.minY + 8
        case .center: preview.midY - height / 2
        case .bottom: preview.maxY - height - 8
        }
        panelFrame = CGRect(
            x: min(max(preview.midX - width / 2, screen.minX + 4), screen.maxX - width - 4),
            y: min(max(y, screen.minY + 4), screen.maxY - height - 4),
            width: width, height: height
        )
        switch style.iconPosition {
        case .above:
            titleFrame = CGRect(x: (width - textWidth) / 2, y: 0, width: textWidth, height: titleHeight)
            iconFrame = CGRect(x: (width - icon) / 2, y: titleHeight + gap, width: icon, height: icon)
        case .below:
            titleFrame = CGRect(x: (width - textWidth) / 2, y: icon + gap, width: textWidth, height: titleHeight)
            iconFrame = CGRect(x: (width - icon) / 2, y: 0, width: icon, height: icon)
        case .leading:
            titleFrame = CGRect(x: icon + gap, y: (height - titleHeight) / 2, width: textWidth, height: titleHeight)
            iconFrame = CGRect(x: 0, y: (height - icon) / 2, width: icon, height: icon)
        case .trailing:
            titleFrame = CGRect(x: 0, y: (height - titleHeight) / 2, width: textWidth, height: titleHeight)
            iconFrame = CGRect(x: textWidth + gap, y: (height - icon) / 2, width: icon, height: icon)
        }
    }
}
