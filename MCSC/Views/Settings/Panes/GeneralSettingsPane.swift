import Cocoa

/// General settings pane: launch at login, window and dock behavior,
/// Mission Control, and feedback options.
final class GeneralSettingsPane: MCSCSettingsPane {
    private var launchAtLoginCheckbox: NSButton!
    private var autoEjectCheckbox: NSButton!
    private var quitAppIfNoWindowsCheckbox: NSButton!
    private var dockActionsCheckbox: NSButton!
    private var titleBarActionsCheckbox: NSButton!
    private var nativeWindowButtonHitExpansionCheckbox: NSButton!
    private var nativeWindowButtonHitScaleControl: WindowButtonScaleControl?
    private var hoverCloseCheckbox: NSButton!
    private var missionControlButtonScaleControl: WindowButtonScaleControl?
    private var missionControlLabelsCheckbox: NSButton!
    private var missionControlLabelStyleControls: MissionControlLabelStyleControls?
    private var keyboardNavCheckbox: NSButton!
    private var spotlightFixCheckbox: NSButton!
    private var hapticCheckbox: NSButton!
    private var cursorFeedbackCheckbox: NSButton!
    private var optimizedAnimationsCheckbox: NSButton!

    override func loadView() {
        view = NSView()

        let layoutView = SettingsLayoutView()
        layoutView.install(in: view)

        // Startup
        let startup = layoutView.addColumnSection(label: "Startup")
        launchAtLoginCheckbox = startup.addDescribedCheckbox(
            title: "Launch at Login",
            description: "Open MCSC automatically when you log in.",
            target: self,
            action: #selector(toggleLaunchAtLogin(_:))
        )

        layoutView.addSeparatorSection()

        // Behavior
        let behavior = layoutView.addColumnSection(label: "Behavior", itemColumnMaximumWidth: 340)
        autoEjectCheckbox = behavior.addDescribedCheckbox(
            title: "Auto-Eject Mounted Volumes",
            description: "Ejects the volume when you close its Finder window.",
            target: self,
            action: #selector(toggleAutoEject(_:))
        )
        behavior.addSpacing(6)
        quitAppIfNoWindowsCheckbox = behavior.addDescribedCheckbox(
            title: "Quit App When Last Window Closes",
            description: "Quits an application when you close its last open window.",
            target: self,
            action: #selector(toggleQuitAppIfNoWindows(_:))
        )
        behavior.addSpacing(6)
        dockActionsCheckbox = behavior.addDescribedCheckbox(
            title: "Dock Gestures and Shortcuts",
            description: "Enables gestures and Command shortcuts while hovering over Dock icons.",
            target: self,
            action: #selector(toggleDockActions(_:))
        )
        behavior.addSpacing(6)
        titleBarActionsCheckbox = behavior.addDescribedCheckbox(
            title: "Title Bar Gestures and Shortcuts",
            description: "Enables gestures and Command shortcuts while hovering over a window title bar.",
            target: self,
            action: #selector(toggleTitleBarActions(_:))
        )
        behavior.addSpacing(6)
        nativeWindowButtonHitExpansionCheckbox = behavior.addDescribedCheckbox(
            title: "Enlarge Window Button Hit Areas",
            description: "Makes the red, yellow, and green window buttons easier to click while preserving their appearance.",
            target: self,
            action: #selector(toggleNativeWindowButtonHitExpansion(_:))
        )
        nativeWindowButtonHitExpansionCheckbox.setAccessibilityIdentifier("nativeWindowButtonHitExpansion")
        behavior.addSpacing(6)
        let nativeScaleControl = WindowButtonScaleControl(
            title: "Hit Area:",
            accessibilityLabel: "Native window button hit area scale",
            identifier: "nativeWindowButtonHitScale",
            range: 1 ... 3
        )
        nativeScaleControl.onChange = { [weak self] scale in
            self?.viewModel.nativeWindowButtonHitScale = scale
        }
        nativeWindowButtonHitScaleControl = nativeScaleControl
        behavior.addCustomView(nativeScaleControl, verticalAlignment: .top)

        layoutView.addSeparatorSection()

        buildMissionControlAndFeedbackSections(on: layoutView)

        sizePaneToFitContent(minimumWidth: Self.minimumPaneWidth)
        installScrollingViewport()
        refresh()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        guard let scrollView = view as? GeneralSettingsScrollView else { return }
        let viewportSize = scrollingViewportSize(for: scrollView.contentSizeBeforeScrolling)
        guard viewportSize != scrollView.preferredViewportSize else { return }
        scrollView.preferredViewportSize = viewportSize
        scrollView.setFrameSize(viewportSize)
        capturePreferredPaneSize()
        minimumPaneSize = viewportSize
        tabViewController?.invalidateCachedSize(for: self)
    }

    private func installScrollingViewport() {
        let documentView = view
        let contentSize = preferredPaneSize ?? documentView.frame.size
        let scrollView = GeneralSettingsScrollView(
            contentSize: contentSize,
            viewportSize: scrollingViewportSize(for: contentSize)
        )
        documentView.autoresizingMask = [.width]
        scrollView.documentView = documentView
        view = scrollView
        scrollView.layoutSubtreeIfNeeded()
        // The existing document uses AppKit's bottom-up coordinates.
        scrollView.contentView.scroll(to: NSPoint(
            x: 0,
            y: max(0, documentView.bounds.height - scrollView.contentSize.height)
        ))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        capturePreferredPaneSize()
        minimumPaneSize = scrollView.preferredViewportSize
    }

    private func scrollingViewportSize(for contentSize: NSSize) -> NSSize {
        let window = view.window ?? tabViewController?.view.window
        guard let screen = window?.screen ?? NSScreen.main else { return contentSize }
        let availableRect: NSRect = if let window {
            window.contentRect(forFrameRect: screen.visibleFrame)
        } else {
            NSWindow.contentRect(
                forFrameRect: screen.visibleFrame,
                styleMask: [.titled, .closable]
            )
        }
        return NSSize(width: contentSize.width, height: min(contentSize.height, max(1, availableRect.height)))
    }

    /// Mission Control, Feedback, and Restore Defaults sections.
    private func buildMissionControlAndFeedbackSections(on layoutView: SettingsLayoutView) {
        // Mission Control
        let missionControl = layoutView.addColumnSection(label: "Mission Control", itemColumnMaximumWidth: 340)
        hoverCloseCheckbox = missionControl.addDescribedCheckbox(
            title: "Hover Window Controls",
            description: "Shows clickable close, minimize, and fullscreen buttons on window thumbnails. "
                + "Tap × to close the window; hold for 0.75 seconds to quit the app. Releasing a hold early cancels. "
                + "With ×: ⌘ force quits, ⌥ minimizes, and ⌃ toggles fullscreen.",
            target: self,
            action: #selector(toggleHoverClose(_:))
        )
        missionControl.addSpacing(6)
        let missionControlScaleControl = WindowButtonScaleControl(
            title: "Button Size:",
            accessibilityLabel: "Mission Control window button size",
            identifier: "missionControlButtonScale",
            range: 0.75 ... 2
        )
        missionControlScaleControl.onChange = { [weak self] scale in
            self?.viewModel.missionControlButtonScale = scale
        }
        missionControlButtonScaleControl = missionControlScaleControl
        missionControl.addCustomView(missionControlScaleControl, verticalAlignment: .top)
        missionControl.addSpacing(6)
        missionControlLabelsCheckbox = missionControl.addDescribedCheckbox(
            title: "Always Show Window Labels",
            description: "Shows titles and app icons on window thumbnails. Hovered windows use the system label.",
            target: self,
            action: #selector(toggleMissionControlLabels(_:))
        )
        missionControl.addSpacing(6)
        let labelStyleControls = MissionControlLabelStyleControls()
        labelStyleControls.onChange = { [weak self] style in
            self?.viewModel.missionControlLabelStyle = style
        }
        missionControlLabelStyleControls = labelStyleControls
        missionControl.addCustomView(labelStyleControls, verticalAlignment: .top)
        missionControl.addSpacing(6)
        keyboardNavCheckbox = missionControl.addDescribedCheckbox(
            title: "Keyboard Navigation",
            description: "Cycle through thumbnails with Tab and Shift-Tab, then press Return to activate. Type to filter windows by title.",
            target: self,
            action: #selector(toggleKeyboardNav(_:))
        )
        missionControl.addSpacing(6)
        spotlightFixCheckbox = missionControl.addDescribedCheckbox(
            title: "Spotlight Shortcut (⌘Space)",
            description: "Allows ⌘Space to open Spotlight while Mission Control is open.",
            target: self,
            action: #selector(toggleSpotlightFix(_:))
        )

        layoutView.addSeparatorSection()

        // Feedback
        let feedback = layoutView.addColumnSection(label: "Feedback", itemColumnMaximumWidth: 340)
        hapticCheckbox = feedback.addDescribedCheckbox(
            title: "Haptic Feedback",
            description: "Provides trackpad haptics when gestures or shortcuts trigger.",
            target: self,
            action: #selector(toggleHaptics(_:))
        )
        feedback.addSpacing(6)
        cursorFeedbackCheckbox = feedback.addDescribedCheckbox(
            title: "Cursor Feedback Overlay",
            description: "Briefly displays an icon next to the cursor when an action runs.",
            target: self,
            action: #selector(toggleCursorFeedback(_:))
        )
        feedback.addSpacing(6)
        optimizedAnimationsCheckbox = feedback.addDescribedCheckbox(
            title: "Reduced Animation Overhead",
            description: "Uses lightweight CoreAnimation effects instead of native symbol effects. Requires restarting MCSC.",
            target: self,
            action: #selector(toggleOptimizedAnimations(_:))
        )

        layoutView.addSeparatorSection()

        layoutView.addButtonSection(title: "Restore Defaults",
                                    alignment: .trailing,
                                    widthMode: .contentBlock,
                                    target: self,
                                    action: #selector(restoreDefaults(_:)))
    }

    override func refresh() {
        launchAtLoginCheckbox?.state = viewModel.isLaunchAtLoginEnabled ? .on : .off
        autoEjectCheckbox?.state = viewModel.isAutoEjectEnabled ? .on : .off
        quitAppIfNoWindowsCheckbox?.state = viewModel.isQuitAppIfNoWindowsEnabled ? .on : .off
        dockActionsCheckbox?.state = viewModel.isDockActionsOutsideMCEnabled ? .on : .off
        titleBarActionsCheckbox?.state = viewModel.isTitleBarActionsOutsideMCEnabled ? .on : .off
        nativeWindowButtonHitExpansionCheckbox?.state = viewModel.isNativeWindowButtonHitExpansionEnabled ? .on : .off
        hoverCloseCheckbox?.state = viewModel.isHoverCloseButtonEnabled ? .on : .off
        refreshWindowButtonScaleControls()
        missionControlLabelsCheckbox?.state = viewModel.isMissionControlLabelsEnabled ? .on : .off
        refreshMissionControlLabelStyleControls()
        keyboardNavCheckbox?.state = viewModel.isKeyboardNavigationEnabled ? .on : .off
        spotlightFixCheckbox?.state = viewModel.isCmdSpaceEnabled ? .on : .off
        hapticCheckbox?.state = viewModel.isHapticFeedbackEnabled ? .on : .off
        cursorFeedbackCheckbox?.state = viewModel.isCursorFeedbackEnabled ? .on : .off
        optimizedAnimationsCheckbox?.state = viewModel.isOptimizedAnimationModeEnabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        viewModel.toggleLaunchAtLogin()
        sender.state = viewModel.isLaunchAtLoginEnabled ? .on : .off
    }

    @objc private func toggleAutoEject(_ sender: NSButton) {
        viewModel.isAutoEjectEnabled.toggle()
        sender.state = viewModel.isAutoEjectEnabled ? .on : .off
    }

    @objc private func toggleQuitAppIfNoWindows(_ sender: NSButton) {
        viewModel.isQuitAppIfNoWindowsEnabled.toggle()
        sender.state = viewModel.isQuitAppIfNoWindowsEnabled ? .on : .off
    }

    @objc private func toggleDockActions(_ sender: NSButton) {
        viewModel.isDockActionsOutsideMCEnabled.toggle()
        sender.state = viewModel.isDockActionsOutsideMCEnabled ? .on : .off
    }

    @objc private func toggleTitleBarActions(_ sender: NSButton) {
        viewModel.isTitleBarActionsOutsideMCEnabled.toggle()
        sender.state = viewModel.isTitleBarActionsOutsideMCEnabled ? .on : .off
    }

    @objc private func toggleHoverClose(_ sender: NSButton) {
        viewModel.isHoverCloseButtonEnabled.toggle()
        sender.state = viewModel.isHoverCloseButtonEnabled ? .on : .off
        refreshWindowButtonScaleControls()
    }

    @objc private func toggleNativeWindowButtonHitExpansion(_ sender: NSButton) {
        viewModel.isNativeWindowButtonHitExpansionEnabled.toggle()
        sender.state = viewModel.isNativeWindowButtonHitExpansionEnabled ? .on : .off
        refreshWindowButtonScaleControls()
    }

    private func refreshWindowButtonScaleControls() {
        nativeWindowButtonHitScaleControl?.refresh(
            scale: viewModel.nativeWindowButtonHitScale,
            isEnabled: viewModel.isNativeWindowButtonHitExpansionEnabled
        )
        missionControlButtonScaleControl?.refresh(
            scale: viewModel.missionControlButtonScale,
            isEnabled: viewModel.isHoverCloseButtonEnabled
        )
    }

    @objc private func toggleMissionControlLabels(_ sender: NSButton) {
        viewModel.isMissionControlLabelsEnabled.toggle()
        sender.state = viewModel.isMissionControlLabelsEnabled ? .on : .off
        refreshMissionControlLabelStyleControls()
    }

    private func refreshMissionControlLabelStyleControls() {
        missionControlLabelStyleControls?.refresh(
            style: viewModel.missionControlLabelStyle,
            isEnabled: viewModel.isMissionControlLabelsEnabled
        )
    }

    @objc private func toggleHaptics(_ sender: NSButton) {
        viewModel.isHapticFeedbackEnabled.toggle()
        sender.state = viewModel.isHapticFeedbackEnabled ? .on : .off
    }

    @objc private func toggleCursorFeedback(_ sender: NSButton) {
        viewModel.isCursorFeedbackEnabled.toggle()
        sender.state = viewModel.isCursorFeedbackEnabled ? .on : .off
    }

    @objc private func toggleOptimizedAnimations(_ sender: NSButton) {
        viewModel.isOptimizedAnimationModeEnabled.toggle()
        sender.state = viewModel.isOptimizedAnimationModeEnabled ? .on : .off

        let alert = NSAlert()
        alert.messageText = "Restart MCSC?"
        alert.informativeText = "MCSC must restart for this change to take effect."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Later")

        if let window = view.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    Self.relaunchApp()
                }
            }
        } else {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                Self.relaunchApp()
            }
        }
    }

    private static func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func toggleKeyboardNav(_ sender: NSButton) {
        viewModel.isKeyboardNavigationEnabled.toggle()
        sender.state = viewModel.isKeyboardNavigationEnabled ? .on : .off
    }

    @objc private func toggleSpotlightFix(_ sender: NSButton) {
        viewModel.isCmdSpaceEnabled.toggle()
        sender.state = viewModel.isCmdSpaceEnabled ? .on : .off
    }

    @objc private func restoreDefaults(_: NSButton) {
        viewModel.isAutoEjectEnabled = true
        viewModel.isQuitAppIfNoWindowsEnabled = false
        viewModel.isDockActionsOutsideMCEnabled = false
        viewModel.isTitleBarActionsOutsideMCEnabled = false
        viewModel.isNativeWindowButtonHitExpansionEnabled = true
        viewModel.nativeWindowButtonHitScale = 1.6
        viewModel.isHoverCloseButtonEnabled = true
        viewModel.missionControlButtonScale = 1.25
        viewModel.isMissionControlLabelsEnabled = false
        viewModel.missionControlLabelStyle = MissionControlLabelStyle()
        viewModel.isKeyboardNavigationEnabled = true
        viewModel.isCmdSpaceEnabled = true
        viewModel.isHapticFeedbackEnabled = true
        viewModel.isCursorFeedbackEnabled = true
        viewModel.isOptimizedAnimationModeEnabled = true
        refreshAllPanes()
    }
}

/// Gives the root pane a measured viewport size without constraining its document height.
private final class GeneralSettingsScrollView: NSScrollView {
    let contentSizeBeforeScrolling: NSSize
    var preferredViewportSize: NSSize {
        didSet { invalidateIntrinsicContentSize() }
    }

    init(contentSize: NSSize, viewportSize: NSSize) {
        contentSizeBeforeScrolling = contentSize
        preferredViewportSize = viewportSize
        super.init(frame: NSRect(origin: .zero, size: viewportSize))
        borderType = .noBorder
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        horizontalScrollElasticity = .none
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override var intrinsicContentSize: NSSize {
        preferredViewportSize
    }
}
