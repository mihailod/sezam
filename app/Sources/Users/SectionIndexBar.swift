import SwiftUI

/// The Contacts-style A–Z strip. SwiftUI has no equivalent of UITableView's
/// sectionIndexTitles, so it is drawn by hand: tap or drag to jump.
struct SectionIndexBar: View {
    let titles: [String]
    var onSelect: (String) -> Void

    @State private var lastSent: String?

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(titles, id: \.self) { title in
                    Text(title)
                        // Deliberately fixed: up to 27 buckets must fit the
                        // screen height, so this strip cannot scale with the
                        // rest of the app.
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tint)
                        // Without this, "500" wraps to "50"/"0" and a year
                        // breaks across two lines.
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !titles.isEmpty else { return }
                        let slot = geo.size.height / CGFloat(titles.count)
                        let idx = min(titles.count - 1, max(0, Int(value.location.y / slot)))
                        let title = titles[idx]
                        // Dragging fires continuously; only act on a new bucket.
                        if title != lastSent {
                            lastSent = title
                            onSelect(title)
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                    .onEnded { _ in lastSent = nil }
            )
        }
        .frame(width: barWidth)
        .padding(.trailing, 2)
    }

    /// Sized to the longest label: single letters need 20pt, magnitude buckets
    /// ("1k+", "500") need more, and years ("1994") more still.
    private var barWidth: CGFloat {
        switch titles.map(\.count).max() ?? 1 {
        case 0...1: return 20
        case 2...3: return 30
        default:    return 38
        }
    }
}
