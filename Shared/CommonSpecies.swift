import Foundation

/// Common tree species for quick selection in the Watch app
let commonSpecies: [String] = [
    // Fruit trees
    "Apple",
    "Cherry",
    "Pear",
    "Plum",
    "Damson",
    "Sloe",
    "Apricot",
    "Peach",
    "Quince",
    "Mulberry",
    "Fig",
    "Persimmon",

    // Nut trees
    "Walnut",
    "Chestnut",
    "Hazel",
    "Almond",
    "Pecan",

    // Deciduous
    "Oak",
    "Maple",
    "Birch",
    "Beech",
    "Ash",
    "Elm",
    "Lime",
    "Poplar",
    "Willow",
    "Alder",
    "Hornbeam",
    "Sycamore",
    "Horse Chestnut",
    "Rowan",

    // Evergreen
    "Pine",
    "Spruce",
    "Fir",
    "Cedar",
    "Yew",
    "Holly",
    "Juniper",
    "Cypress",
    "Redwood",
    "Larch"
]

/// Tidies a species name the user dictated or typed. A name on the common
/// list takes the list's spelling; one the user capitalised themselves is kept
/// as given; an all-lowercase one (typical of dictation) gets each word
/// capitalised.
func formattedSpeciesName(_ input: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if let known = commonSpecies.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
        return known
    }
    if trimmed != trimmed.lowercased() {
        return trimmed
    }
    return trimmed.capitalized
}
