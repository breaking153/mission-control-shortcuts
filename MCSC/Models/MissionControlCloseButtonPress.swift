import CoreGraphics
import Foundation

/// One physical press; monotonic deadlines keep release/timer ordering deterministic.
struct MissionControlCloseButtonPress {
    enum Action { case closeWindow, quitApplication }

    static let tapDuration: TimeInterval = 0.25
    static let holdDuration: TimeInterval = 0.75
    let windowID: CGWindowID
    let processID: pid_t
    let sessionGeneration: UInt
    let buttonFrame: CGRect
    let deadline: TimeInterval
    private(set) var isCancelled = false
    private(set) var isTriggered = false

    func contains(_ point: CGPoint) -> Bool {
        buttonFrame.contains(point)
    }

    mutating func updatePointer(_ point: CGPoint) {
        if !contains(point) {
            isCancelled = true
        }
    }

    mutating func action(at point: CGPoint, now: TimeInterval, isRelease: Bool) -> Action? {
        updatePointer(point)
        guard !isCancelled, !isTriggered else { return nil }
        if now >= deadline {
            isTriggered = true
            return .quitApplication
        }
        guard isRelease else { return nil }
        let elapsed = now - (deadline - Self.holdDuration)
        if elapsed >= 0, elapsed <= Self.tapDuration {
            isTriggered = true
            return .closeWindow
        }
        isCancelled = true
        return nil
    }
}
