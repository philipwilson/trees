import SwiftUI

struct TreeRowView: View {
    let tree: Tree

    var body: some View {
        HStack(spacing: 12) {
            if let firstPhoto = tree.treePhotos.first,
               let uiImage = ImageDownsampler.downsample(data: firstPhoto.imageData, maxDimension: 50) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "tree.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .frame(width: 50, height: 50)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(tree.species.isEmpty ? "Unknown Species" : tree.species)
                    .font(.headline)

                if let variety = tree.variety, !variety.isEmpty {
                    Text(variety)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(tree.coordinateString)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(tree.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                AccuracyBadge(accuracy: tree.horizontalAccuracy)

                if !tree.treePhotos.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "photo")
                            .font(.caption2)
                        Text("\(tree.treePhotos.count)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
    }
}

#Preview {
    List {
        TreeRowView(tree: Tree(
            latitude: 45.123456,
            longitude: -122.654321,
            horizontalAccuracy: 3.5,
            species: "Apple",
            variety: "Honeycrisp"
        ))
        TreeRowView(tree: Tree(
            latitude: 45.123456,
            longitude: -122.654321,
            horizontalAccuracy: 12.0,
            species: "Red Maple"
        ))
    }
}
