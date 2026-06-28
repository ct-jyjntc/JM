import SwiftUI

struct LoadingStateView: View {
    let title: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "arrow.clockwise")
        } description: {
            ProgressView()
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

struct ErrorStateView: View {
    let title: String
    let message: String
    let retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("重试", systemImage: "arrow.clockwise", action: retry)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "tray")
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}
