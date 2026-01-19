import SwiftUI

struct ContentView: View {
    @State private var showingCapture = false
    @State private var lastCapturedTree: WatchTree?
    @State private var connectivityManager = WatchConnectivityManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Button {
                        showingCapture = true
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "tree.fill")
                                .font(.system(size: 40))
                            Text("Capture Tree")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    if let tree = lastCapturedTree {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last Captured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(tree.species.isEmpty ? "Unknown" : tree.species)
                                .font(.headline)
                            Text(tree.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }

                    if !connectivityManager.pendingTrees.isEmpty {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("\(connectivityManager.pendingTrees.count) pending sync")
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
                .padding()
            }
            .navigationTitle("Tree Tracker")
            .sheet(isPresented: $showingCapture) {
                CaptureView { tree in
                    lastCapturedTree = tree
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
