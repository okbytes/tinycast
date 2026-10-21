import SwiftUI

/// What a row hands to the app it is dropped on, and the image that follows the pointer there.
struct RowDragItem {
    let writer: any NSPasteboardWriting
    let image: NSImage

    /// `image` is the row's warm tile: a decode on mouse-down stalls the frame the drag begins on.
    static func file(_ url: URL, image: NSImage?) -> RowDragItem {
        RowDragItem(writer: url as NSURL, image: image ?? NSWorkspace.shared.icon(forFile: url.path))
    }
}

/// A row another app can take. Copy only, so a user's file, an app or an owned blob never moves.
struct RowDrag {
    /// Read when the drag starts, not when the row draws; nil refuses the drag.
    let item: () -> RowDragItem?
    /// A landed drop only; a refused one flies back to the row, so a drag that did nothing says so.
    let dropped: () -> Void
}

/// What one press on a row does. A per-row catcher holds one; a list's catcher resolves one per press.
struct RowPress {
    enum Activation {
        /// On the press of a double click: a list beside a preview selects with a single one.
        case doubleClick
        /// On a single click's release, which is the moment a press is known not to be a drag.
        case release
    }

    let activation: Activation
    let select: () -> Void
    let activate: () -> Void
    /// The right-click action; nil leaves right presses to whatever sits beneath the catcher.
    var actions: (() -> Void)? = nil
    var drag: RowDrag? = nil
}

/// The frames of a list's rows in the list's own coordinate space, kept outside SwiftUI state: a
/// write re-renders nothing, and the list's one `ListPressCatcher` reads them per press.
@MainActor
final class RowFrames {
    private var frames: [String: CGRect] = [:]

    func set(_ frame: CGRect, for id: String) {
        frames[id] = frame
    }

    func remove(_ id: String) {
        frames[id] = nil
    }

    /// Among `ids` only: a row the lazy stack dropped can still hold a frame another row now fills.
    func id(at point: CGPoint, among ids: Set<String>) -> String? {
        frames.first { ids.contains($0.key) && $0.value.contains(point) }?.key
    }
}

extension View {
    /// Selects on the press rather than a double-click interval later; a double click activates.
    func onRowClick(
        select: @escaping () -> Void, activate: @escaping () -> Void, drag: RowDrag? = nil
    ) -> some View {
        overlay(
            RowPressCatcher(
                press: RowPress(activation: .doubleClick, select: select, activate: activate, drag: drag)))
    }

    /// Publishes this row's frame in `space` for the list's `ListPressCatcher`; the catcher needs it
    /// on every row it serves. The frame is dropped with the row, so a dropped row cannot be hit.
    func reportRowFrame(_ id: String, to frames: RowFrames, in space: String) -> some View {
        onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(space))
        } action: {
            frames.set($0, for: id)
        }
        .onDisappear { frames.remove(id) }
    }

    /// One AppKit catcher for a whole list, in place of one or two per row: a press resolves the row
    /// under the point from the frames `reportRowFrame` publishes. Apply to the stack that owns the
    /// coordinate space the rows report in. Measured, two platform views per row were ~13% of a
    /// keystroke's CPU in the launcher.
    func listPressCatcher(resolve: @escaping (CGPoint) -> RowPress?) -> some View {
        overlay(ListPressCatcher(resolve: resolve))
    }
}

/// AppKit, not `onDrag`: only an `NSDraggingSource` can force `.copy` over a same-volume move.
private struct RowPressCatcher: NSViewRepresentable {
    let press: RowPress

    func makeNSView(context: Context) -> RowPressView { RowPressView() }

    func updateNSView(_ view: RowPressView, context: Context) {
        let press = press
        view.resolve = { _ in press }
    }
}

private struct ListPressCatcher: NSViewRepresentable {
    let resolve: (CGPoint) -> RowPress?

    func makeNSView(context: Context) -> RowPressView { RowPressView() }

    func updateNSView(_ view: RowPressView, context: Context) {
        view.resolve = resolve
    }
}

/// Owns the whole left press, because the hosting view otherwise eats the click first.
private final class RowPressView: NSView, NSDraggingSource {
    private static let dragSlop: CGFloat = 4

    /// The press for a point in this view's (flipped, SwiftUI-like) coordinates; nil declines it.
    var resolve: (CGPoint) -> RowPress? = { _ in nil }

    /// Top-left origin, so a resolved point matches the frames SwiftUI reported.
    override var isFlipped: Bool { true }

    /// Left presses, and right ones only where the press has actions: anything else falls through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        switch NSApp.currentEvent?.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return resolve(local) != nil ? super.hitTest(point) : nil
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return resolve(local)?.actions != nil ? super.hitTest(point) : nil
        default:
            return nil
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        resolve(convert(event.locationInWindow, from: nil))?.actions?()
    }

    override func mouseDown(with event: NSEvent) {
        guard let press = resolve(convert(event.locationInWindow, from: nil)) else { return }
        press.select()
        if press.activation == .doubleClick {
            guard event.clickCount < 2 else {
                press.activate()
                return
            }
            guard press.drag != nil else { return }
        }
        guard pressBecomesDrag() else {
            if press.activation == .release { press.activate() }
            return
        }
        guard let item = press.drag?.item() else { return }
        beginDrag(item, with: event, dropped: press.drag?.dropped)
    }

    /// Tracks the press itself until it is released or leaves the slop.
    private func pressBecomesDrag() -> Bool {
        guard let window else { return false }
        // Deltas off `mouseLocation`, so no coordinate conversion can drift.
        let start = NSEvent.mouseLocation
        var passedSlop = false
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { tracked, stop in
            guard let tracked, tracked.type != .leftMouseUp else {
                stop.pointee = true
                return
            }
            let mouse = NSEvent.mouseLocation
            guard hypot(mouse.x - start.x, mouse.y - start.y) > Self.dragSlop else { return }
            passedSlop = true
            stop.pointee = true
        }
        return passedSlop
    }

    /// Held for the session's end, which outlives the press that resolved it.
    private var dropped: (() -> Void)?

    private func beginDrag(_ item: RowDragItem, with event: NSEvent, dropped: (() -> Void)?) {
        self.dropped = dropped
        let image = item.image
        let dragging = NSDraggingItem(pasteboardWriter: item.writer)
        // Sized to the image and centred on the cursor. The row's shape would stretch a thumbnail.
        let origin = convert(event.locationInWindow, from: nil)
        dragging.setDraggingFrame(
            NSRect(
                x: origin.x - image.size.width / 2, y: origin.y - image.size.height / 2,
                width: image.size.width, height: image.size.height),
            contents: image)
        let session = beginDraggingSession(with: [dragging], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        let dropped = dropped
        self.dropped = nil
        guard operation != [] else { return }
        dropped?()
    }
}
