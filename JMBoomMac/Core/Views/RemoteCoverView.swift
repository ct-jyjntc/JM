import SwiftUI

struct RemoteCoverView: View {
    let title: String
    let imageURL: String
    let hideCover: Bool

    var body: some View {
        ZStack {
            if let url = URL(string: imageURL), !imageURL.isEmpty {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            if hideCover {
                Rectangle()
                    .fill(.regularMaterial)
                Image(systemName: "eye.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(AppTheme.coverAspectRatio, contentMode: .fit)
        .background(.quaternary)
        .clipped()
        .accessibilityLabel(title)
    }
}
