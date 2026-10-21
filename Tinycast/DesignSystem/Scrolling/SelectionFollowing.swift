import SwiftUI

extension View {
    /// Publishes the selected row's frame for `scrollFollowsSelection`; only that row measures.
    func selectionFrame(_ selected: Bool) -> some View {
        overlay {
            if selected {
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: SelectionFrameKey.self, value: geometry.frame(in: .scrollView))
                }
            }
        }
    }

    /// Keeps the keyboard selection in the band between the bars; needs `selectionFrame` on rows.
    /// `intent` is read inside the modifier, so the view that owns the request never re-renders for it.
    func scrollFollowsSelection(
        intent: @escaping () -> ScrollIntent, row: String?, atOrigin: Bool, proxy: ScrollViewProxy
    ) -> some View {
        modifier(SelectionFollowing(intent: intent, row: row, atOrigin: atOrigin, proxy: proxy))
    }
}

private struct SelectionFrameKey: PreferenceKey {
    static var defaultValue: CGRect? { nil }

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = value ?? nextValue()
    }
}

private struct SelectionFollowing: ViewModifier {
    let intent: () -> ScrollIntent
    let row: String?
    let atOrigin: Bool
    let proxy: ScrollViewProxy

    @State private var band = Band(insetTop: 0, height: 0)
    @State private var selection: CGRect?
    /// Where the selection is still owed a place; nil once it has one, and the pointer owns it.
    @State private var target: Target?

    /// The geometry the rule reads: the band's height, and the inset whose settling moves the rest.
    private struct Band: Equatable {
        var insetTop: CGFloat
        var height: CGFloat
    }

    private enum Target {
        /// Anywhere inside the band, by the least movement.
        case band
        /// The band's middle, which needs the row's measured frame to land exactly.
        case middle
    }

    func body(content: Content) -> some View {
        let scroll = intent()
        return content
            .onScrollGeometryChange(for: Band.self) {
                Band(insetTop: $0.contentInsets.top, height: $0.containerSize.height)
            } action: { old, new in
                band = new
                // The inset settles after mount and moves the resting offset: restate a landing.
                let kind = intent().kind
                if old.insetTop != new.insetTop, kind != .follow {
                    return begin(kind)
                }
                align()
            }
            .onPreferenceChange(SelectionFrameKey.self) { frame in
                selection = frame
                align()
            }
            .onChange(of: scroll) { _, scroll in begin(scroll.kind) }
    }

    private func begin(_ kind: ScrollIntent.Kind) {
        switch kind {
        case .top:
            target = nil
            proxy.scrollToOrigin()
        case .follow:
            target = .band
            align()
        case .center:
            target = .middle
            align()
        }
    }

    private func align() {
        guard let target, let row else { return }
        // Origin, not the row's top, so the first row's section header stays on screen.
        if atOrigin {
            self.target = nil
            return proxy.scrollToOrigin()
        }
        // The lazy stack dropped the selected row: bring it back by id, then re-check its frame.
        guard let selection else {
            return proxy.scrollTo(row, anchor: target == .middle ? .center : nil)
        }
        // A measured row centres exactly, so there is nothing left to watch for.
        if target == .middle {
            self.target = nil
            return proxy.scrollTo(row, anchor: .center)
        }
        guard
            let edge = SelectionReveal.edge(
                rowTop: selection.minY, rowBottom: selection.maxY, band: band.height)
        else {
            self.target = nil
            return
        }
        proxy.scrollTo(row, anchor: edge == .top ? .top : .bottom)
    }
}
extension View {
    /// Marks the content top as the `scrollToOrigin` target; apply after the padding.
    func scrollOriginAnchor() -> some View {
        overlay(alignment: .top) {
            Color.clear.frame(height: 0).id(ScrollOrigin.id)
        }
    }

}

private enum ScrollOrigin {
    nonisolated static let id = "scroll-origin-anchor"
}

extension ScrollViewProxy {
    /// Restores the exact resting offset; needs `scrollOriginAnchor()` on the content.
    func scrollToOrigin() {
        scrollTo(ScrollOrigin.id, anchor: .top)
    }
}
