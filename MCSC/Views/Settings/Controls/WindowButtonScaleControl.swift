import Cocoa

/// A small native slider shared by window-button size preferences.
final class WindowButtonScaleControl: NSView {
    var onChange: ((Double) -> Void)?

    private let slider: NSSlider
    private let valueLabel = NSTextField(labelWithString: "100%")
    private let titleLabel: NSTextField

    init(title: String, accessibilityLabel: String, identifier: String, range: ClosedRange<Double>) {
        slider = NSSlider(value: range.lowerBound * 100,
                          minValue: range.lowerBound * 100,
                          maxValue: range.upperBound * 100,
                          target: nil,
                          action: nil)
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        slider.target = self
        slider.action = #selector(scaleChanged(_:))
        slider.isContinuous = false
        slider.numberOfTickMarks = Int(((range.upperBound - range.lowerBound) / 0.05).rounded()) + 1
        slider.allowsTickMarkValuesOnly = true
        slider.identifier = NSUserInterfaceItemIdentifier(identifier)
        slider.setAccessibilityIdentifier(identifier)
        slider.setAccessibilityLabel(accessibilityLabel)
        slider.setAccessibilityHelp("Adjust from \(Int(range.lowerBound * 100))% to \(Int(range.upperBound * 100))%.")
        titleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        let row = NSStackView(views: [titleLabel, slider, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 330)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// Setting a native control's value does not dispatch its action.
    func refresh(scale: Double, isEnabled: Bool) {
        slider.doubleValue = scale * 100
        slider.isEnabled = isEnabled
        titleLabel.textColor = isEnabled ? .secondaryLabelColor : .disabledControlTextColor
        valueLabel.textColor = isEnabled ? .secondaryLabelColor : .disabledControlTextColor
        updateValueLabel()
    }

    private func updateValueLabel() {
        valueLabel.stringValue = "\(Int(slider.doubleValue.rounded()))%"
        slider.setAccessibilityValueDescription(valueLabel.stringValue)
    }

    @objc private func scaleChanged(_ sender: NSSlider) {
        updateValueLabel()
        onChange?(sender.doubleValue / 100)
    }
}
