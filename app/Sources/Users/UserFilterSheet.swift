import SwiftUI

/// Faceted filter over the user directory.
///
/// City and company are long tails -- 628 and 1,508 values, and 96% of the
/// companies belong to exactly one person -- so each list opens on its most
/// common entries and expands on request. Searching is not enough on its own
/// here: half these employers are defunct Yugoslav firms nobody would think to
/// type, so the full list has to stay reachable by browsing.
struct UserFilterSheet: View {
    let cityFacets: [Facet]
    let companyFacets: [Facet]
    let yearFacets: [Facet]
    let regionFacets: [Facet]
    let matchCount: Int
    @Binding var filter: UserFilter

    @Environment(\.dismiss) private var dismiss

    /// Enough rows to browse without burying the sections underneath.
    private static let collapsedRows = 8

    @State private var citySearch = ""
    @State private var companySearch = ""
    @State private var regionSearch = ""
    @State private var cityExpanded = false
    @State private var companyExpanded = false
    @State private var regionExpanded = false

    var body: some View {
        NavigationStack {
            List {
                facetSection("City", .city, cityFacets,
                             search: $citySearch, expanded: $cityExpanded)
                facetSection("Company", .company, companyFacets,
                             search: $companySearch, expanded: $companyExpanded)

                Section("Year Joined") {
                    // 11 short values: a wrapping row of chips reads faster and
                    // costs a third of the height of 11 list rows.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)],
                              spacing: 8) {
                        ForEach(yearFacets) { facet in
                            YearChip(facet: facet,
                                     selected: filter.contains(facet.id, in: .year)) {
                                filter.toggle(facet.id, in: .year)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                facetSection("Region · Country", .region, regionFacets,
                             search: $regionSearch, expanded: $regionExpanded)
            }
            .navigationTitle("Filter on:")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear All") { filter = UserFilter() }
                        .disabled(filter.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            // A safe-area inset rather than a .bottomBar toolbar item: the
            // toolbar squeezes a bare Text into a circular glass button and
            // truncates it to "No f...".
            .safeAreaInset(edge: .bottom) {
                // The point of a filter is the size of the result, so it is
                // shown live rather than discovered after dismissing.
                Text(filter.isEmpty
                     ? "No filter · \(matchCount.formatted()) users"
                     : "\(matchCount.formatted()) of \(UserFilterSheet.total(cityFacets).formatted()) users")
                    .font(.footnote)
                    .foregroundStyle(matchCount == 0 ? .red : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.bar)
            }
        }
    }

    private static func total(_ facets: [Facet]) -> Int {
        facets.reduce(0) { $0 + $1.count }
    }

    @ViewBuilder
    private func facetSection(_ title: String, _ section: FilterSection,
                              _ facets: [Facet],
                              search: Binding<String>,
                              expanded: Binding<Bool>) -> some View {
        let matches = filtered(facets, search.wrappedValue)
        // A search is itself a request to see everything that matches, so
        // typing overrides the collapsed state without touching it.
        let searching = !search.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
        let shown = (expanded.wrappedValue || searching)
            ? matches : Array(matches.prefix(Self.collapsedRows))

        Section {
            FacetSearchField(text: search, placeholder: "Search \(title.lowercased())")

            ForEach(shown) { facet in
                FacetRow(facet: facet, checked: filter.contains(facet.id, in: section)) {
                    filter.toggle(facet.id, in: section)
                }
            }

            if matches.isEmpty {
                Text("No match").font(.footnote).foregroundStyle(.secondary)
            } else if !searching && matches.count > Self.collapsedRows {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expanded.wrappedValue.toggle()
                    }
                } label: {
                    Label(expanded.wrappedValue
                          ? "Show fewer"
                          : "Show all \(matches.count.formatted())",
                          systemImage: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.footnote)
                }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                let picked = filter.count(in: section)
                if picked > 0 {
                    Text("\(picked) selected").font(.caption2).foregroundStyle(.tint)
                }
            }
        }
    }

    /// Matched on the folded key as well as the label, so typing "nis" finds
    /// Niš and "racunari" finds Računari.
    private func filtered(_ facets: [Facet], _ query: String) -> [Facet] {
        let q = SearchQuery.fold(query.trimmingCharacters(in: .whitespaces)).lowercased()
        guard !q.isEmpty else { return facets }
        return facets.filter {
            $0.id.contains(q) || SearchQuery.fold($0.label).lowercased().contains(q)
        }
    }
}

/// A plain `TextField` in a list row rather than `.searchable`: the sheet needs
/// two independent search fields, one per section, and `.searchable` supplies
/// only one per navigation stack.
private struct FacetSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.footnote).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FacetRow: View {
    let facet: Facet
    let checked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? AnyShapeStyle(.tint)
                                             : AnyShapeStyle(.secondary))
                Text(facet.label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(facet.count.formatted())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct YearChip: View {
    let facet: Facet
    let selected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 1) {
                Text(facet.label).font(.subheadline.weight(.medium))
                Text(facet.count.formatted()).font(.caption2)
                    .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.8))
                                              : AnyShapeStyle(.secondary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                        in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
