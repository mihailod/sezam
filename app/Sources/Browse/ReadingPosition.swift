import SwiftUI
import UIKit

/// Holds a thread's reading place through anything that re-lays-out its rows
/// without the reader scrolling: a text size change in Settings or Control
/// Center, and a trip to another app.
///
/// `List` remembers where it is as a scroll offset in points. When every row
/// changes height at once that offset no longer names the same text -- and in
/// practice the list loses its place entirely: reading the end of message #1,
/// one text size step landed on #29. So the place is kept as *which message*
/// is under the top edge and how far into it the reader is, and restored from
/// that.
///
/// Updated continuously as the reader scrolls, and frozen the moment something
/// disruptive begins -- the screen leaving view, the app going inactive, the
/// text size changing -- so the re-layout cannot overwrite the place it is
/// about to destroy.
@MainActor
final class ReadingPosition {
    static let space = "thread-reading"

    private struct Mark {
        let id: Int64
        /// Points from the message's top down to the reading edge. Negative
        /// when the message starts below the edge.
        let into: CGFloat
        let height: CGFloat
    }

    /// Frames of the rows currently laid out. Deliberately not observable:
    /// they change on every scroll frame, and publishing them would re-render
    /// the thread for nothing.
    private var frames: [Int64: CGRect] = [:]
    /// The visible band, in the list's coordinate space. Its top is not 0:
    /// rows scroll under the navigation bar, so reading starts below it
    /// (128 pt on an iPhone 16), which is also where `scrollTo(.top)` puts a row.
    private var edge: CGFloat = 0
    private var visibleHeight: CGFloat = 0
    private var mark: Mark?
    private var frozen = false
    /// Several triggers can fire for one disruption -- coming back from the
    /// Settings tab after a size change is both a reappearance and a size
    /// change -- and two restores applying the same correction moved the
    /// reader twice as far. Only the newest may act.
    private var generation = 0
    private var typeSize: DynamicTypeSize?
    /// The list's own scroll view. SwiftUI's `scrollTo` can only put a row's
    /// top, centre or bottom at an edge -- a fractional anchor measured as a
    /// centred scroll -- so going back part-way into a long message needs the
    /// offset set directly, in points.
    weak var scrollView: UIScrollView?

    func rowMoved(_ id: Int64, to frame: CGRect) {
        frames[id] = frame
        guard !frozen else { return }
        let bottom = edge + visibleHeight
        guard let top = frames.filter({ $0.value.maxY > edge && $0.value.minY < bottom })
                              .min(by: { $0.value.minY < $1.value.minY }) else { return }
        mark = Mark(id: top.key, into: edge - top.value.minY, height: top.value.height)
    }

    func rowGone(_ id: Int64) { frames[id] = nil }

    func viewportChanged(top: CGFloat, height: CGFloat) {
        edge = top
        visibleHeight = height
    }

    /// Called from the view's body, which runs before the new layout does, so a
    /// size change freezes the place while it still describes the old layout.
    func observe(typeSize new: DynamicTypeSize) {
        if let typeSize, typeSize != new { frozen = true }
        typeSize = new
    }

    func freeze() { frozen = true }

    /// For a re-sort: the old place belongs to rows that are gone.
    func forget() {
        mark = nil
        frames = [:]
        frozen = false
    }

    /// Puts the frozen place back, if the layout moved it.
    func restore(using proxy: ScrollViewProxy) async {
        generation += 1
        let turn = generation
        // A superseded restore must not thaw the place under the newer one.
        defer { if turn == generation { frozen = false } }
        guard let mark else { return }
        // Let the new layout land before judging whether it moved anything.
        try? await Task.sleep(for: .milliseconds(80))
        guard turn == generation else { return }
        if let now = frames[mark.id], abs((edge - now.minY) - mark.into) < 1,
           abs(now.height - mark.height) < 1 {
            return
        }

        // A row far from where the list now is has not been laid out, so it
        // has no height to measure. Bringing it to the edge makes the list lay
        // it out; a row already on screen needs no such step.
        if frames[mark.id] == nil {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(mark.id, anchor: .top) }
            try? await Task.sleep(for: .milliseconds(80))
            guard turn == generation else { return }
        }
        guard let row = frames[mark.id], let scrollView else { return }

        // Part-way in, the same *fraction* of the message: the text has
        // reflowed, and the line that was at the edge now sits about that far
        // down the taller or shorter message. Above it, the same gap in points.
        let into = mark.into > 0 ? mark.into * row.height / mark.height : mark.into
        let shift = (edge - into) - row.minY
        guard abs(shift) >= 1 else { return }
        let inset = scrollView.adjustedContentInset
        let lowest = -inset.top
        let highest = max(lowest, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        let y = min(max(scrollView.contentOffset.y - shift, lowest), highest)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
        // The layout this produces arrives while still frozen, so record the
        // place here; otherwise the next disruption restores the old numbers.
        self.mark = Mark(id: mark.id, into: into, height: row.height)
        // Stay frozen until that layout has landed, so its intermediate frames
        // cannot overwrite the place just recorded.
        try? await Task.sleep(for: .milliseconds(80))
    }
}

/// Reports the scroll view a row sits in. A zero-size, non-interactive view
/// that looks up its superview chain once it is in a window.
struct EnclosingScrollView: UIViewRepresentable {
    let found: (UIScrollView) -> Void

    func makeUIView(context: Context) -> Probe { Probe(found: found) }
    func updateUIView(_ uiView: Probe, context: Context) {}

    final class Probe: UIView {
        private let found: (UIScrollView) -> Void

        init(found: @escaping (UIScrollView) -> Void) {
            self.found = found
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var view = superview
            while let current = view {
                if let scroll = current as? UIScrollView {
                    found(scroll)
                    return
                }
                view = current.superview
            }
        }
    }
}
