import SwiftUI
import SwiftData

struct SpeciesTextField: View {
    @Binding var text: String
    @Environment(\.modelContext) private var modelContext
    @State private var allSpecies: [String] = []
    @State private var suggestions: [String] = []
    @State private var showingSuggestions = false
    @FocusState private var isFocused: Bool
    @State private var filterTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Species", text: $text)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        updateSuggestions()
                    } else {
                        showingSuggestions = false
                    }
                }
                .onChange(of: text) { _, _ in
                    updateSuggestionsDebounced()
                }

            if showingSuggestions && !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
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

    /// Debounce filtering to avoid lag on every keystroke
    private func updateSuggestionsDebounced() {
        filterTask?.cancel()
        filterTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            if !Task.isCancelled {
                await MainActor.run {
                    updateSuggestions()
                }
            }
        }
    }

    /// Filter suggestions based on current text
    private func updateSuggestions() {
        guard isFocused, !text.isEmpty else {
            suggestions = []
            showingSuggestions = false
            return
        }
        let lowercasedText = text.lowercased()
        let filtered = allSpecies.filter { species in
            species.lowercased().contains(lowercasedText) && species.lowercased() != lowercasedText
        }
        suggestions = Array(filtered.prefix(5))
        showingSuggestions = !suggestions.isEmpty
    }

    /// Load species list once on appear
    private func loadSpecies() {
        // Start with common species immediately
        allSpecies = commonSpecies.sorted()

        // Fetch existing species on the main actor where modelContext is valid
        Task { @MainActor in
            var descriptor = FetchDescriptor<Tree>()
            descriptor.propertiesToFetch = [\.species]

            do {
                let trees = try modelContext.fetch(descriptor)
                let existingSpecies = Set(trees.map { $0.species }.filter { !$0.isEmpty })
                let combined = existingSpecies.union(Set(commonSpecies))
                allSpecies = combined.sorted()
            } catch {
                // Keep using common species on error
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
