import Foundation

/// How a tree list is ordered.
enum TreeSortOrder: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case species
    case accuracy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "Newest First"
        case .oldest: return "Oldest First"
        case .species: return "Species A–Z"
        case .accuracy: return "Most Accurate First"
        }
    }

    /// "apple" and "Apple" are the same name here, so trees typed with
    /// different capitalisation sort together.
    private static func compareNames(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive, .numeric], locale: .current)
    }

    func sorted(_ trees: [Tree]) -> [Tree] {
        switch self {
        case .newest:
            return trees.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return trees.sorted { $0.createdAt < $1.createdAt }
        case .species:
            return trees.sorted { lhs, rhs in
                // Unnamed trees go last rather than first
                if lhs.species.isEmpty != rhs.species.isEmpty { return rhs.species.isEmpty }
                let order = Self.compareNames(lhs.species, rhs.species)
                if order != .orderedSame { return order == .orderedAscending }
                let varietyOrder = Self.compareNames(lhs.variety ?? "", rhs.variety ?? "")
                if varietyOrder != .orderedSame { return varietyOrder == .orderedAscending }
                return lhs.createdAt > rhs.createdAt
            }
        case .accuracy:
            return trees.sorted { lhs, rhs in
                // Unknown accuracy is stored as zero but is not "most accurate"
                if lhs.hasKnownAccuracy != rhs.hasKnownAccuracy { return lhs.hasKnownAccuracy }
                if lhs.horizontalAccuracy != rhs.horizontalAccuracy {
                    return lhs.horizontalAccuracy < rhs.horizontalAccuracy
                }
                return lhs.createdAt > rhs.createdAt
            }
        }
    }
}

/// Which collection's trees to show.
enum CollectionFilter: Hashable {
    case all
    case unassigned
    case collection(UUID)
}

/// Narrows the trees shown in a list or on the map. Shared by both so
/// "show me the Bramleys in the north orchard" means the same thing everywhere.
struct TreeFilter: Equatable {
    var collection: CollectionFilter = .all
    /// Nil shows every species
    var species: String?

    var isActive: Bool {
        collection != .all || species != nil
    }

    func includes(_ tree: Tree) -> Bool {
        switch collection {
        case .all:
            break
        case .unassigned:
            if tree.collection != nil { return false }
        case .collection(let id):
            if tree.collection?.id != id { return false }
        }
        if let species, Self.normalized(tree.species) != Self.normalized(species) {
            return false
        }
        return true
    }

    /// Applies the filter, then the search text, then the sort order.
    func apply(to trees: [Tree], searchText: String = "", sortOrder: TreeSortOrder? = nil) -> [Tree] {
        var result = isActive ? trees.filter(includes) : trees
        if !searchText.isEmpty {
            result = result.filter { $0.matches(searchText: searchText) }
        }
        return sortOrder?.sorted(result) ?? result
    }

    /// Distinct species for the filter menu: case-insensitive, first spelling
    /// seen wins, unnamed trees left out.
    static func speciesOptions(in trees: [Tree]) -> [String] {
        var seen = Set<String>()
        var options: [String] = []
        for tree in trees {
            let key = normalized(tree.species)
            if !key.isEmpty, seen.insert(key).inserted {
                options.append(tree.species.trimmingCharacters(in: .whitespaces))
            }
        }
        return options.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespaces)
    }
}
