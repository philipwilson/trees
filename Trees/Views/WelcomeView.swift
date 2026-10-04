import SwiftUI

/// Shown once, the first time the app opens with no trees, to say what the
/// app is for and how to start.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "tree.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Welcome to Tree Tracker")
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    Text("Record exactly where your trees are, and what you know about them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                VStack(alignment: .leading, spacing: 20) {
                    feature(
                        "location.fill", .blue, "Capture a tree",
                        "Stand at the tree and tap +. Wait for the accuracy to settle, then save its position."
                    )
                    feature(
                        "note.text", .orange, "Keep its history",
                        "Add the species and variety, photos, and dated notes as the tree grows."
                    )
                    feature(
                        "map.fill", .green, "Find it again",
                        "See every tree on the map, group them into collections, and get directions back."
                    )
                    feature(
                        "applewatch", .pink, "Capture from your wrist",
                        "The Apple Watch app records a tree and sends it to your iPhone."
                    )
                    feature(
                        "icloud.fill", .cyan, "Your data stays yours",
                        "Trees sync through your own iCloud, and export to CSV, JSON or GPX whenever you like."
                    )
                }

                Button {
                    dismiss()
                } label: {
                    Text("Get Started")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private func feature(_ systemImage: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WelcomeView()
}
