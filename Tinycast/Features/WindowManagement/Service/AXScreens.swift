import AppKit

/// The one Cocoa↔AX converter. See docs/features/window-management.md#coordinate-space.
struct AXGeometry {
    let anchorHeight: CGFloat

    /// Snapshot once per command: `NSScreen.screens` can change, and mixing anchors corrupts.
    @MainActor
    init(screens: [NSScreen]) {
        let primary = screens.first { $0.frame.origin == .zero } ?? screens.first
        anchorHeight = primary?.frame.height ?? 0
    }

    /// An involution through `maxY`, never scaled. docs/features/window-management.md
    func flip(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x, y: anchorHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// Displays, converted into the AX space the geometry layer works in.
@MainActor
enum AXScreens {
    /// Cocoa screens flipped through one snapshotted anchor, never one each.
    static func converted(
        _ screens: [NSScreen], geometry: AXGeometry
    ) -> [WindowPlacementEngine.Screen] {
        screens.enumerated().map { index, screen in
            // A display with no number still needs a stable, collision-free id for this call.
            return WindowPlacementEngine.Screen(
                id: displayID(screen).map(Int.init) ?? -(index + 1),
                frame: geometry.flip(screen.frame),
                usableFrame: geometry.flip(belowMenuBar(screen)))
        }
    }

    /// Tiles cover the Dock, which never sits on the top edge, so only the menu bar is kept clear.
    private static func belowMenuBar(_ screen: NSScreen) -> CGRect {
        let frame = screen.frame
        return CGRect(
            x: frame.minX, y: frame.minY, width: frame.width,
            height: screen.visibleFrame.maxY - frame.minY)
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
    }
}
