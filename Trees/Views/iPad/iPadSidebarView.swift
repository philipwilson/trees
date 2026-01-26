import SwiftUI

struct iPadSidebarView: View {
    @Binding var selection: iPadContentView.SidebarSection
    let treeCount: Int
    let collectionCount: Int

    var body: some View {
        List {
            Section {
                Button {
                    selection = .trees
                } label: {
                    Label {
                        HStack {
                            Text("Trees")
                            Spacer()
                            Text("\(treeCount)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    } icon: {
                        Image(systemName: "tree.fill")
                            .foregroundStyle(.green)
                    }
                }
                .listRowBackground(selection == .trees ? Color.accentColor.opacity(0.2) : nil)

                Button {
                    selection = .collections
                } label: {
                    Label {
                        HStack {
                            Text("Collections")
                            Spacer()
                            Text("\(collectionCount)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    } icon: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .listRowBackground(selection == .collections ? Color.accentColor.opacity(0.2) : nil)

                Button {
                    selection = .map
                } label: {
                    Label("Map", systemImage: "map.fill")
                }
                .listRowBackground(selection == .map ? Color.accentColor.opacity(0.2) : nil)
            } header: {
                Text("Navigation")
            }
        }
        .buttonStyle(.plain)
        .navigationTitle("Tree Tracker")
        .listStyle(.sidebar)
    }
}

#Preview {
    NavigationSplitView {
        iPadSidebarView(
            selection: .constant(.trees),
            treeCount: 42,
            collectionCount: 5
        )
    } detail: {
        Text("Detail")
    }
}
