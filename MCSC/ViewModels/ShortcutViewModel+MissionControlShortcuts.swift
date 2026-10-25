import Cocoa

@MainActor
extension ShortcutViewModel {
    func syncMissionControlShortcuts() {
        guard missionControlService.isMissionControlActive else {
            missionControlShortcutService?.stop()
            return
        }
        var bindings = Set(config.shortcutBindings.values)
        if config.isCmdSpaceEnabled {
            bindings.insert(ShortcutBinding(keyCode: ShortcutActionRouter.kKeySpace))
        }
        guard !bindings.isEmpty else {
            missionControlShortcutService?.stop()
            return
        }
        if missionControlShortcutService == nil {
            let service = MissionControlShortcutService()
            service.onShortcut = { [weak self] binding, location in
                guard let self else { return }
                let generation = self.missionControlShortcutService?.generation
                // A hotkey queued during the exit animation must never act on
                // an unrelated ordinary window after overview has closed.
                guard self.missionControlService.checkMissionControlActive(force: true) else {
                    self.missionControlShortcutService?.stop()
                    AppLogger.eventTap.debug("Discarded native shortcut after overview exit")
                    return
                }
                // The scan can discover a rapid close/reopen and restart the
                // service. An event from that previous overview must expire.
                guard self.missionControlShortcutService?.generation == generation else { return }
                var flags: CGEventFlags = .maskCommand
                if binding.includesShift {
                    flags.insert(.maskShift)
                }
                _ = self.handleShortcut(keyCode: binding.keyCode, flags: flags, location: location)
            }
            missionControlShortcutService = service
        }
        missionControlShortcutService?.start(bindings: bindings)
    }
}
