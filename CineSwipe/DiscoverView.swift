import SwiftData
import SwiftUI

struct DiscoverView: View {
    @ObservedObject var viewModel: CineSwipeViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var isShowingFilter = false
    @State private var requestedAction: CardAction?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.isLoading && viewModel.queue.isEmpty {
                    loadingState
                } else if let current = viewModel.queue.first {
                    ForEach(Array(viewModel.queue.prefix(2).reversed())) {
                        media in
                        let isCurrent = media.id == current.id
                        DiscoverCard(
                            media: media,
                            isCurrent: isCurrent,
                            isEnabled: isCurrent
                                && !viewModel.isCommittingAction,
                            requestedAction: $requestedAction
                        ) { action in
                            await viewModel.perform(
                                action,
                                on: media,
                                in: modelContext
                            )
                        }
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height
                        )
                        .allowsHitTesting(isCurrent)
                        .accessibilityHidden(!isCurrent)
                    }
                } else {
                    emptyState
                }

                VStack {
                    Spacer()

                    if !viewModel.queue.isEmpty {
                        actionBar
                            .padding(.bottom, 168)
                    }
                }

                VStack {
                    Spacer()
                    if !viewModel.isLoading || !viewModel.queue.isEmpty {
                        HStack {
                            Spacer()
                            Button {
                                isShowingFilter = true
                            } label: {
                                Image(
                                    systemName: viewModel.isFilterActive
                                        ? "line.3.horizontal.decrease.circle.fill"
                                        : "line.3.horizontal.decrease"
                                )
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(
                                    viewModel.isFilterActive ? .yellow : .white
                                )
                                .frame(width: 48, height: 48)
                            }
                            .adaptiveGlass(in: Circle())
                            .accessibilityLabel(
                                viewModel.isFilterActive ? "筛选，已启用" : "筛选"
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 248)
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingFilter) {
            FilterView(viewModel: viewModel)
        }
        .sensoryFeedback(.success, trigger: viewModel.feedbackTrigger)
    }

    private var actionBar: some View {
        HStack(spacing: 34) {
            DiscoverActionControl(
                title: "跳过",
                systemImage: "xmark",
                tint: .red
            ) {
                performButtonAction(.skip)
            }

            DiscoverActionControl(
                title: "想看",
                systemImage: "bookmark.fill",
                tint: .yellow
            ) {
                performButtonAction(.wantToWatch)
            }

            DiscoverActionControl(
                title: "已看",
                systemImage: "checkmark",
                tint: .green
            ) {
                performButtonAction(.watched)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("正在挑选今天的片单…")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
            Text(emptyStateMessage)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            if viewModel.isFilterActive {
                HStack {
                    Button("调整筛选") {
                        isShowingFilter = true
                    }
                    .buttonStyle(.bordered)

                    Button("重置筛选") {
                        Task {
                            await viewModel.resetFilter(in: modelContext)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            } else {
                Button("重试") {
                    Task {
                        await viewModel.loadDiscover(
                            in: modelContext,
                            resetSession: true
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
        .padding(28)
        .padding(.bottom, 80)
    }

    private var emptyStateMessage: String {
        if let error = viewModel.errorMessage {
            return error
        }
        if viewModel.isFilterActive {
            return "这组条件有点挑剔，换几个试试看吧。"
        }
        return "暂时没有更多啦，换个条件再逛逛吧。"
    }

    private var emptyStateIcon: String {
        viewModel.errorMessage == nil ? "film.stack" : "wifi.exclamationmark"
    }

    private func performButtonAction(_ action: CardAction) {
        guard !viewModel.queue.isEmpty, !viewModel.isCommittingAction else {
            return
        }
        requestedAction = action
    }

}

private struct DiscoverCard: View {
    let media: MediaItem
    let isCurrent: Bool
    let isEnabled: Bool
    @Binding var requestedAction: CardAction?
    let onAction: (CardAction) async -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGSize = .zero
    @State private var isSubmitting = false

    private let triggerDistance: CGFloat = 105

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                DiscoverPosterArtwork(media: media)

                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.44),
                        .init(color: .black.opacity(0.12), location: 0.62),
                        .init(color: .black.opacity(0.68), location: 0.84),
                        .init(color: .black.opacity(0.92), location: 1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack {
                    actionHint
                        .padding(.top, 56)
                    Spacer()
                    metadata
                        .padding(.horizontal, 24)
                        .padding(.bottom, 278)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .offset(offset)
            .gesture(
                dragGesture(in: proxy.size),
                isEnabled: isEnabled && !isSubmitting
            )
            .onChange(of: requestedAction) { _, action in
                guard isCurrent, let action else { return }
                requestedAction = nil
                commit(action, in: proxy.size)
            }
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                offset = value.translation
            }
            .onEnded { value in
                let action = resolvedAction(for: value.translation)
                guard let action else {
                    resetPosition()
                    return
                }
                commit(action, in: size)
            }
    }

    @ViewBuilder
    private var actionHint: some View {
        if let action = resolvedAction(for: offset) {
            Label(action.title, systemImage: action.systemImage)
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.black.opacity(0.7), in: Capsule())
                .transition(.opacity)
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(media.localizedTitle)
                .font(.title2.bold())
                .lineLimit(2)
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                Label(media.ratingText, systemImage: "star.fill")
                    .foregroundStyle(.yellow)
                if let year = media.releaseYear {
                    metadataTag(String(year))
                }
                metadataTag(media.mediaType.displayName)
            }
            .font(.subheadline.weight(.semibold))

            if !media.genreNames.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(media.genreNames.prefix(2)), id: \.self) {
                        metadataTag($0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataTag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.white.opacity(0.16), in: Capsule())
    }

    private func resolvedAction(for translation: CGSize) -> CardAction? {
        if translation.width > triggerDistance {
            return .wantToWatch
        }
        if translation.width < -triggerDistance {
            return .skip
        }
        if translation.height < -triggerDistance,
           abs(translation.height) > abs(translation.width) {
            return .watched
        }
        return nil
    }

    private func resetPosition() {
        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.32, dampingFraction: 0.82)
        withAnimation(animation) {
            offset = .zero
        }
    }

    private func commit(_ action: CardAction, in size: CGSize) {
        guard isCurrent, !isSubmitting else { return }
        isSubmitting = true

        withAnimation(.easeIn(duration: 0.24)) {
            offset = exitOffset(for: action, in: size)
        }

        Task {
            try? await Task.sleep(for: .milliseconds(220))
            let succeeded = await onAction(action)
            if !succeeded {
                isSubmitting = false
                resetPosition()
            }
        }
    }

    private func exitOffset(for action: CardAction, in size: CGSize) -> CGSize {
        switch action {
        case .skip:
            CGSize(width: -max(size.width * 1.25, 500), height: 0)
        case .wantToWatch:
            CGSize(width: max(size.width * 1.25, 500), height: 0)
        case .watched:
            CGSize(width: 0, height: -max(size.height * 1.1, 900))
        }
    }

    private var accessibilityDescription: String {
        let year = media.releaseYear.map(String.init) ?? "年份未知"
        let genres = media.genreNames.prefix(2).joined(separator: "、")
        return [
            media.localizedTitle,
            media.mediaType.displayName,
            year,
            media.ratingText,
            genres
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "，")
    }
}

private struct DiscoverPosterArtwork: View {
    let media: MediaItem

    var body: some View {
        GeometryReader { proxy in
            AsyncImage(url: media.posterURL()) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height,
                            alignment: .center
                        )
                        .clipped()
                case .empty:
                    ZStack {
                        Color(red: 0.08, green: 0.09, blue: 0.11)
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white.opacity(0.8))
                    }
                case .failure:
                    BrandedPosterPlaceholder(
                        title: media.localizedTitle
                    )
                @unknown default:
                    BrandedPosterPlaceholder(
                        title: media.localizedTitle
                    )
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .accessibilityLabel(media.localizedTitle)
    }
}

private struct DiscoverActionControl: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            IconActionButton(
                title: title,
                systemImage: systemImage,
                tint: tint,
                action: action
            )

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 58)
        .accessibilityElement(children: .combine)
    }
}
