import AppKit

enum NotchMetrics {
    /// Size of the expanded notch.
    static let openSize = CGSize(width: 540, height: 196)
    /// Extra transparent room around the open notch so its shadow isn't clipped.
    static let shadowPadding: CGFloat = 24

    static let closedTopRadius: CGFloat = 6
    static let closedBottomRadius: CGFloat = 10
    static let openTopRadius: CGFloat = 14
    static let openBottomRadius: CGFloat = 28

    /// Width of the fake notch drawn on displays without a camera notch.
    static let fakeNotchWidth: CGFloat = 190
}

/// Where the notch sits on a given screen, in screen coordinates (origin bottom-left).
struct NotchGeometry: Equatable {
    let screenFrame: NSRect
    let hasHardwareNotch: Bool
    /// Size of the physical notch, or of the fake notch on notchless displays.
    let notchSize: CGSize

    init(screen: NSScreen) {
        screenFrame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            hasHardwareNotch = true
            notchSize = CGSize(
                width: screen.frame.width - left.width - right.width,
                height: screen.safeAreaInsets.top
            )
        } else {
            hasHardwareNotch = false
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            notchSize = CGSize(
                width: NotchMetrics.fakeNotchWidth,
                height: menuBarHeight > 0 ? menuBarHeight : NSStatusBar.system.thickness
            )
        }
    }

    /// The built-in display if it has a notch, otherwise the display with the menu bar.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    /// Frame of the panel window: the open notch plus shadow padding.
    var windowFrame: NSRect {
        let width = NotchMetrics.openSize.width + NotchMetrics.shadowPadding * 2
        let height = NotchMetrics.openSize.height + NotchMetrics.shadowPadding
        return NSRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
    }

    /// A rect of `size` hanging from the top centre of the screen.
    func rectHangingFromTop(_ size: CGSize) -> NSRect {
        NSRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }
}
