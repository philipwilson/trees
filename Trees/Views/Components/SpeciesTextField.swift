import SwiftUI
import SwiftData

struct SpeciesTextField: View {
    @Binding var text: String
    @Environment(\.modelContext) private var modelContext
    @State private var allSpecies: [String] = []
    @State private var showingSuggestions = false
    @FocusState private var isFocused: Bool

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
        .onAppear {
            loadSpecies()
        }
    }

    /// Load species list once on appear, not on every keystroke
    private func loadSpecies() {
        // Fetch only species strings, not full Tree objects
        let descriptor = FetchDescriptor<Tree>()
        do {
            let trees = try modelContext.fetch(descriptor)
            let existingSpecies = Set(trees.map { $0.species }.filter { !$0.isEmpty })
            let combined = existingSpecies.union(Set(commonSpecies))
            allSpecies = combined.sorted()
        } catch {
            // Fall back to just common species
            allSpecies = commonSpecies.sorted()
        }
    }
}

#Preview {
    Form {
        SpeciesTextField(text: .constant("App"))
    }
    .modelContainer(for: Tree.self, inMemory: true)
}
