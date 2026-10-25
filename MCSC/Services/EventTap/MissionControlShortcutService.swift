import Carbon.HIToolbox
import Cocoa

/// Registers specific chords with WindowServer instead of inspecting keyboard
/// input. The owner starts this service only while Mission Control is open.
final class MissionControlShortcutService {
    var onShortcut: ((ShortcutBinding, CGPoint) -> Void)?

    private struct Registration {
        let binding: ShortcutBinding
        let reference: EventHotKeyRef
    }

    private static let signature: OSType = 0x4D43_5348
    private var handler: EventHandlerRef?
    private var registrations: [UInt32: Registration] = [:]
    private var registeredBindings: Set<ShortcutBinding> = []
    private var requestedBindings: Set<ShortcutBinding> = []
    /// Do not recycle an ID when an old session's event is still queued.
    private var nextID: UInt32 = 1
    private(set) var generation: UInt64 = 0

    var registeredCount: Int {
        registrations.count
    }

    func owns(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard flags.contains(.maskCommand),
              flags.isDisjoint(with: [.maskControl, .maskAlternate]) else { return false }
        return registeredBindings.contains(ShortcutBinding(
            keyCode: keyCode, includesShift: flags.contains(.maskShift)
        ))
    }

    func start(bindings: Set<ShortcutBinding>) {
        guard handler == nil || requestedBindings != bindings else { return }
        stop()
        guard !bindings.isEmpty else { return }

        var kind = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let service = Unmanaged<MissionControlShortcutService>.fromOpaque(context).takeUnretainedValue()
            return service.handle(event)
        }, 1, &kind, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else {
            AppLogger.eventTap.error("Mission Control hotkey handler failed: status=\(result, privacy: .public)")
            return
        }
        requestedBindings = bindings
        for binding in bindings.sorted(by: {
            $0.keyCode == $1.keyCode ? !$0.includesShift && $1.includesShift : $0.keyCode < $1.keyCode
        }) {
            guard let keyCode = UInt32(exactly: binding.keyCode), nextID < UInt32.max else { continue }
            let id = nextID
            nextID += 1
            let modifiers = UInt32(cmdKey) | (binding.includesShift ? UInt32(shiftKey) : 0)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(keyCode, modifiers,
                                             EventHotKeyID(signature: Self.signature, id: id),
                                             GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference {
                registrations[id] = Registration(binding: binding, reference: reference)
                registeredBindings.insert(binding)
            } else {
                AppLogger.eventTap.warning(
                    "Mission Control hotkey unavailable: key=\(keyCode, privacy: .public), status=\(status, privacy: .public)"
                )
            }
        }
        AppLogger.eventTap
            .info("Mission Control native shortcuts registered: count=\(self.registeredCount, privacy: .public)")
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var id = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
            id.signature == Self.signature, let registration = registrations[id.id] else {
            return OSStatus(eventNotHandledErr)
        }
        onShortcut?(registration.binding, CGEvent(source: nil)?.location ?? .zero)
        return noErr
    }

    func stop() {
        generation &+= 1
        let count = registrations.count
        for registration in registrations.values {
            UnregisterEventHotKey(registration.reference)
        }
        registrations.removeAll(keepingCapacity: false)
        registeredBindings.removeAll(keepingCapacity: false)
        requestedBindings.removeAll(keepingCapacity: false)
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
        if count > 0 {
            AppLogger.eventTap.info("Mission Control native shortcuts unregistered: count=\(count, privacy: .public)")
        }
    }

    deinit { stop() }
}
