import SwiftData
import SwiftUI

struct LibraryView: View {
    let status: LibraryStatus
    @ObservedObject var viewModel: CineSwipeViewModel

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LibraryItem.createdAt, order: .reverse)
    private var allItems: [LibraryItem]
    @State private var pendingDeletion: LibraryItem?

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 3
    )

    private var items: [LibraryItem] {
        allItems.filter { $0.status == status }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(items) { item in
                                LibraryGridItem(
                                    item: item,
                                    status: status,
                                    onMove: { move(item) },
                                    onDelete: { pendingDeletion = item }
                                )
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 92)
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(status.title)
        }
        .confirmationDialog(
            "确认删除",
            isPresented: deletionPresented,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let pendingDeletion {
                    viewModel.delete(pendingDeletion, in: modelContext)
                }
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .task(id: allItems.count) {
            await viewModel.refreshMetadata(
                for: allItems,
                in: modelContext
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(status.title, systemImage: emptyIcon)
        } description: {
            Text(emptyMessage)
        } actions: {
            Button("去发现") {
                viewModel.selectedTab = .discover
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(.bottom, 72)
    }

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var emptyIcon: String {
        status == .wantToWatch ? "bookmark" : "checkmark.circle"
    }

    private var emptyMessage: String {
        switch status {
        case .wantToWatch:
            "片单还空着，去发现一部让你心动的吧。"
        case .watched:
            "这里还没有作品，下一部好片正在等你。"
        }
    }

    private var deleteConfirmationMessage: String {
        "从“\(status.title)”中删除这部作品吗？之后它可能再次出现在发现页。"
    }

    private func move(_ item: LibraryItem) {
        let destination: LibraryStatus = status == .wantToWatch
            ? .watched
            : .wantToWatch
        viewModel.move(item, to: destination, in: modelContext)
    }
}

private struct LibraryGridItem: View {
    let item: LibraryItem
    let status: LibraryStatus
    let onMove: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RemotePoster(media: item.media, contentMode: .fill)
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(item.localizedTitle)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .frame(height: 32, alignment: .topLeading)

            Label(item.media.ratingText, systemImage: "star.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
                .lineLimit(1)

            HStack(spacing: 4) {
                Button(action: onMove) {
                    Image(systemName: moveIcon)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(moveLabel)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .accessibilityLabel("删除 \(item.localizedTitle)")
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
    }

    private var moveIcon: String {
        status == .wantToWatch ? "checkmark.circle" : "bookmark"
    }

    private var moveLabel: String {
        status == .wantToWatch
            ? "将 \(item.localizedTitle) 标记为已看"
            : "将 \(item.localizedTitle) 移回想看"
    }
}
