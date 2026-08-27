import SwiftUI

struct RemotePoster: View {
    let media: MediaItem
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(
            url: media.posterURL(),
            transaction: Transaction(animation: .easeInOut(duration: 0.2))
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .accessibilityLabel(media.localizedTitle)
            case .empty:
                ZStack {
                    Color.white.opacity(0.06)
                    ProgressView()
                        .tint(.white)
                }
            case .failure:
                BrandedPosterPlaceholder(title: media.localizedTitle)
            @unknown default:
                BrandedPosterPlaceholder(title: media.localizedTitle)
            }
        }
    }
}

struct BrandedPosterPlaceholder: View {
    let title: String

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.11)
            VStack(spacing: 10) {
                Image(systemName: "film.stack")
                    .font(.system(size: 36, weight: .light))
                Text("CineSwipe")
                    .font(.headline)
                Text(title)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.72))
            .padding(12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) 海报暂不可用")
    }
}

struct IconActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .adaptiveGlass(in: Circle())
        .accessibilityLabel(title)
    }
}

extension View {
    @ViewBuilder
    func adaptiveGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(.white.opacity(0.12), lineWidth: 0.5)
                }
        }
    }
}
