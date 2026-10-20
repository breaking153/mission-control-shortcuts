import CoreGraphics

/// A visible Mission Control preview, in Quartz / Accessibility coordinates.
struct MissionControlPreview {
    let windowID: CGWindowID
    let frame: CGRect
    let spaceID: Int?
}

/// Presentation data only; no retained AX elements or application objects.
struct MissionControlWindowLabel: Equatable {
    let windowID: CGWindowID
    let processID: Int32
    let title: String
    let previewFrame: CGRect
}
