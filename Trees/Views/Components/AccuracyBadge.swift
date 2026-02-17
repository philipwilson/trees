import SwiftUI

struct AccuracyBadge: View {
    let accuracy: Double

    private var color: Color {
        if accuracy < 5 {
            return .green
        } else if accuracy < 15 {
            return .yellow
        } else {
            return .red
        }
    }

    private var label: String {
        String(format: "%.1fm", accuracy)
    }

    private var qualityDescription: String {
        if accuracy < 5 {
            return "excellent"
        } else if accuracy < 15 {
            return "moderate"
        } else {
            return "poor"
        }
    }

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityLabel("Accuracy \(label), \(qualityDescription)")
    }
}

struct LiveAccuracyView: View {
    let accuracy: Double?
    let isUpdating: Bool

    private var displayAccuracy: String {
        if let accuracy = accuracy {
            return String(format: "%.1f m", accuracy)
        }
        return "---"
    }

    private var color: Color {
        guard let accuracy = accuracy else { return .gray }
        if accuracy < 5 {
            return .green
        } else if accuracy < 10 {
            return .yellow
        } else if accuracy < 20 {
            return .orange
        } else {
            return .red
        }
    }

    private var statusText: String {
        guard let accuracy = accuracy else { return "Acquiring GPS..." }
        if accuracy < 10 {
            return "Excellent accuracy"
        } else if accuracy < 20 {
            return "Good accuracy"
        } else {
            return "Waiting for better signal..."
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                if isUpdating {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                Image(systemName: "location.fill")
                    .foregroundStyle(color)
                Text(displayAccuracy)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(statusText), \(displayAccuracy)")
    }
}

#Preview {
    VStack(spacing: 20) {
        AccuracyBadge(accuracy: 3.2)
        AccuracyBadge(accuracy: 8.5)
        AccuracyBadge(accuracy: 25.0)
        LiveAccuracyView(accuracy: 4.5, isUpdating: true)
        LiveAccuracyView(accuracy: nil, isUpdating: true)
    }
    .padding()
}
