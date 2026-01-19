import SwiftUI
import SwiftData

struct SpeciesTextField: View {
    @Binding var text: String
    @Query private var trees: [Tree]
    @State private var showingSuggestions = false
    @FocusState private var isFocused: Bool

    /// All unique species: combines preset species with previously-used species
    private var allSpecies: [String] {
        let existingSpecies = Set(trees.map { $0.species }.filter { !$0.isEmpty })
        let combined = existingSpecies.union(Set(commonSpecies))
        return combined.sorted()
    }

    /// Filtered suggestions based on current text
    private var suggestions: [String] {
        guard !text.isEmpty else { return [] }
        let lowercasedText = text.lowercased()
        return allSpecies.filter { species in
            species.lowercased().contains(lowercasedText) && species.lowercased() != lowercasedText
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Species", text: $text)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    showingSuggestions = focused && !suggestions.isEmpty
                }
                .onChange(of: text) { _, _ in
                    showingSuggestions = isFocused && !suggestions.isEmpty
                }

            if showingSuggestions && !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions.prefix(5), id: \.self) { suggestion in
                            Button {
                                text = suggestion
                                showingSuggestions = false
                                isFocused = false
                            } label: {
                                Text(suggestion)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray5))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
}

#Preview {
    Form {
        SpeciesTextField(text: .constant("App"))
    }
    .modelContainer(for: Tree.self, inMemory: true)
}
