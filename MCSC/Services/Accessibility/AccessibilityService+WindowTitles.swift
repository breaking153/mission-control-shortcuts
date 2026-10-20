import ApplicationServices
import Cocoa

extension AccessibilityService {
    func windowTitles(for processID: pid_t) -> [CGWindowID: String] {
        let app = appElement(for: processID)
        guard let windows: [AXUIElement] = getAttributeValue(kAXWindowsAttribute, for: app) else { return [:] }
        var titles: [CGWindowID: String] = [:]
        for window in windows {
            var windowID: CGWindowID = 0
            guard _AXUIElementGetWindow(window, &windowID) == .success,
                  let title = getWindowTitle(for: window), !title.isEmpty else { continue }
            titles[windowID] = title
        }
        return titles
    }
}
