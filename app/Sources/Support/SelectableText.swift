import SwiftUI
import UIKit

/// Message text you can select part of, with "Copy Message" added to the menu.
///
/// SwiftUI's own `Text` with `.textSelection(.enabled)` offers all or nothing
/// inside a list row: a long press takes the whole message and there are no
/// handles to narrow it down. A non-editable `UITextView` is the selectable
/// text UIKit already has, and its edit menu can carry an extra action beside
/// the system's Copy.
struct SelectableText: UIViewRepresentable {
    let text: String
    /// Title and action of the item added beside the system entries.
    let extraTitle: String
    let extraAction: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        // The list scrolls; this view only lays text out, and its full height
        // is what SwiftUI measures below.
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = []
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.extraTitle = extraTitle
        context.coordinator.extraAction = extraAction
        if view.text != text { view.text = text }
        // Monospaced, because these messages are full of box drawing and
        // hand-aligned columns. Scaled against the view's own traits, which is
        // where SwiftUI puts the app's text size -- including the override in
        // Settings, so the in-app slider moves this too.
        let base = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: base, compatibleWith: view.traitCollection)
        view.textColor = .label
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView,
                      context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        let fitted = uiView.sizeThatFits(CGSize(width: width,
                                                height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(extraTitle: extraTitle, extraAction: extraAction)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var extraTitle: String
        var extraAction: () -> Void

        init(extraTitle: String, extraAction: @escaping () -> Void) {
            self.extraTitle = extraTitle
            self.extraAction = extraAction
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            let whole = UIAction(title: extraTitle,
                                 image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                self?.extraAction()
            }
            // Second, right after the system's Copy: iOS fits three entries
            // before the "›", so this stays reachable without opening the
            // overflow, where appending it left it sixth and hidden.
            var children = suggestedActions
            children.insert(whole, at: children.isEmpty ? 0 : 1)
            return UIMenu(children: children)
        }
    }
}
