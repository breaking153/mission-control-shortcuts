import Cocoa

/// Native controls for the small, value-only Mission Control label preferences.
final class MissionControlLabelStyleControls: NSView {
    var onChange: ((MissionControlLabelStyle) -> Void)?

    private let positionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let iconPositionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let iconSizeSlider = NSSlider(value: 32, minValue: 16, maxValue: 64, target: nil, action: nil)
    private let titleSizeSlider = NSSlider(value: 13, minValue: 10, maxValue: 20, target: nil, action: nil)
    private let iconSizeValue = NSTextField(labelWithString: "32 pt")
    private let titleSizeValue = NSTextField(labelWithString: "13 pt")
    private var style = MissionControlLabelStyle()

    init() {
        super.init(frame: .zero)
        positionPopup.addItems(withTitles: MissionControlLabelPosition.allCases.map(\.title))
        iconPositionPopup.addItems(withTitles: MissionControlIconPosition.allCases.map(\.title))
        for popup in [positionPopup, iconPositionPopup] {
            popup.target = self
            popup.action = #selector(positionChanged(_:))
        }
        for slider in [iconSizeSlider, titleSizeSlider] {
            slider.target = self
            slider.action = #selector(sizeChanged(_:))
            slider.isContinuous = false
        }
        // Keep native keyboard and accessibility steps large enough to survive rounding.
        iconSizeSlider.numberOfTickMarks = 13
        iconSizeSlider.allowsTickMarkValuesOnly = true
        titleSizeSlider.numberOfTickMarks = 11
        titleSizeSlider.allowsTickMarkValuesOnly = true
        positionPopup.setAccessibilityLabel("Window label position")
        iconPositionPopup.setAccessibilityLabel("App icon position")
        iconSizeSlider.setAccessibilityLabel("App icon size")
        titleSizeSlider.setAccessibilityLabel("Window title size")

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Label Position:"), positionPopup],
            [NSTextField(labelWithString: "App Icon Position:"), iconPositionPopup],
            [NSTextField(labelWithString: "App Icon Size:"), sizeRow(slider: iconSizeSlider, value: iconSizeValue)],
            [NSTextField(labelWithString: "Title Size:"), sizeRow(slider: titleSizeSlider, value: titleSizeValue)]
        ])
        grid.columnSpacing = 10
        grid.rowSpacing = 6
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.yPlacement = .center
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.topAnchor.constraint(equalTo: topAnchor),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 330)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private func sizeRow(slider: NSSlider, value: NSTextField) -> NSView {
        value.alignment = .right
        value.textColor = .secondaryLabelColor
        value.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        value.widthAnchor.constraint(equalToConstant: 38).isActive = true
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        let row = NSStackView(views: [slider, value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    func refresh(style: MissionControlLabelStyle, isEnabled: Bool) {
        self.style = style.validated
        positionPopup.selectItem(at: MissionControlLabelPosition.allCases.firstIndex(of: self.style.position) ?? 1)
        iconPositionPopup
            .selectItem(at: MissionControlIconPosition.allCases.firstIndex(of: self.style.iconPosition) ?? 0)
        iconSizeSlider.doubleValue = Double(self.style.iconSize)
        titleSizeSlider.doubleValue = Double(self.style.fontSize)
        iconSizeValue.stringValue = "\(Int(self.style.iconSize.rounded())) pt"
        titleSizeValue.stringValue = "\(Int(self.style.fontSize.rounded())) pt"
        for control in [positionPopup, iconPositionPopup, iconSizeSlider, titleSizeSlider] as [NSControl] {
            control.isEnabled = isEnabled
        }
    }

    @objc private func positionChanged(_ sender: NSPopUpButton) {
        if sender === positionPopup {
            guard MissionControlLabelPosition.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
            style.position = MissionControlLabelPosition.allCases[sender.indexOfSelectedItem]
        } else {
            guard MissionControlIconPosition.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
            style.iconPosition = MissionControlIconPosition.allCases[sender.indexOfSelectedItem]
        }
        onChange?(style)
    }

    @objc private func sizeChanged(_ sender: NSSlider) {
        if sender === iconSizeSlider {
            style.iconSize = CGFloat(sender.doubleValue.rounded())
        } else {
            style.fontSize = CGFloat(sender.doubleValue.rounded())
        }
        refresh(style: style, isEnabled: true)
        onChange?(style)
    }
}
