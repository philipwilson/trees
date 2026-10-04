import SwiftUI

/// Where the app's public pages live. Also entered in App Store Connect.
enum AppLinks {
    static let privacyPolicy = URL(string: "https://github.com/philipwilson/trees/blob/main/PRIVACY_POLICY.md")!
    static let support = URL(string: "https://github.com/philipwilson/trees/issues")!
}

/// App version, a plain-language privacy summary, and links to the privacy
/// policy and support. App Review requires the policy to be reachable from
/// inside the app.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingWelcome = false

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "tree.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text("Tree Tracker")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Version \(Self.versionText)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Text("Your trees, photos and notes are stored on this device and, if you use iCloud, in your own private iCloud account so they sync between your devices. The developer cannot see them. There are no accounts, analytics or ads.")
                        .font(.subheadline)
                    Link(destination: AppLinks.privacyPolicy) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                } header: {
                    Text("Privacy")
                }

                Section {
                    Link(destination: AppLinks.support) {
                        Label("Support and Feedback", systemImage: "questionmark.circle")
                    }
                    Button {
                        showingWelcome = true
                    } label: {
                        Label("Show Welcome Guide", systemImage: "sparkles")
                    }
                } header: {
                    Text("Help")
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingWelcome) {
                WelcomeView()
            }
        }
    }
}

#Preview {
    AboutView()
}
