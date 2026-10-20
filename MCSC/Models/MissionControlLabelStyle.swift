import CoreGraphics

enum MissionControlLabelPosition: String, CaseIterable {
    case top, center, bottom

    var title: String {
        switch self {
        case .top: "Top"
        case .center: "Center"
        case .bottom: "Bottom"
        }
    }
}

enum MissionControlIconPosition: String, CaseIterable {
    case above, below, leading, trailing

    var title: String {
        switch self {
        case .above: "Above Title"
        case .below: "Below Title"
        case .leading: "Left of Title"
        case .trailing: "Right of Title"
        }
    }
}

/// Small value-only preferences, validated at the persistence boundary.
struct MissionControlLabelStyle: Equatable {
    var position: MissionControlLabelPosition = .center
    var iconPosition: MissionControlIconPosition = .above
    var iconSize: CGFloat = 32
    var fontSize: CGFloat = 13

    var validated: Self {
        var copy = self
        copy.iconSize = iconSize.isFinite ? min(max(iconSize, 16), 64) : 32
        copy.fontSize = fontSize.isFinite ? min(max(fontSize, 10), 20) : 13
        return copy
    }
}
