import SwiftUI

/// Anything a sort menu can offer: a closed set of cases, each with a label.
protocol SortOption: CaseIterable, Identifiable, Hashable
where AllCases: RandomAccessCollection {
    var label: String { get }
}

/// The sort menu used wherever a list can be re-ordered, so every one of them
/// looks and behaves the same.
///
/// Buttons rather than a Picker: a Section around a Picker does not render its
/// header here, with or without .inline, so the checkmark is drawn by hand.
struct SortMenu<Option: SortOption>: View {
    @Binding var selection: Option
    /// Icon only, for a bar that is already full -- the thread view's title is
    /// two tappable halves that shrink to fit, and a worded label beside them
    /// would squeeze "PCUSER · tekst.procesori" into an ellipsis. The menu's
    /// checkmark still says which order is in force.
    var compact = false

    var body: some View {
        Menu {
            Section("Sort by:") {
                ForEach(Option.allCases) { option in
                    Button {
                        selection = option
                    } label: {
                        if selection == option {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            }
        } label: {
            if compact {
                Image(systemName: "arrow.up.arrow.down")
                    .accessibilityLabel("Sort by \(selection.label)")
            } else {
                Label(selection.label, systemImage: "arrow.up.arrow.down")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote)
            }
        }
    }
}
