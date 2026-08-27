import Combine
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class CineSwipeViewModel: ObservableObject {
    @Published var selectedTab: AppTab = .discover
    @Published private(set) var queue: [MediaItem] = []
    @Published private(set) var genres: [MediaType: [GenreOption]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isRefilling = false
    @Published private(set) var isCommittingAction = false
    @Published var errorMessage: String?
    @Published var alertMessage: String?
    @Published var feedbackTrigger = 0
    @Published private(set) var appliedFilter: DiscoverFilter

    private let service: TMDBService
    private let defaults: UserDefaults
    private var requestedPages: [MediaType: Set<Int>] = [:]
    private var totalPages: [MediaType: Int] = [:]
    private var loadGeneration = UUID()
    private let filterKey = "CineSwipe.appliedFilter"

    init(
        service: TMDBService = TMDBService(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
        appliedFilter = Self.loadFilter(from: defaults)
    }

    var isFilterActive: Bool { !appliedFilter.isDefault }
    var isAPIConfigured: Bool { TMDBService.isConfigured }

    func start(in context: ModelContext) async {
        do {
            try LibraryRepository.cleanExpiredSkips(in: context)
        } catch {
            alertMessage = "本地数据清理失败，请稍后重试。"
        }
        await loadDiscover(in: context, resetSession: true)
    }

    func loadDiscover(
        in context: ModelContext,
        resetSession: Bool
    ) async {
        let generation = UUID()
        loadGeneration = generation
        isLoading = true
        errorMessage = nil

        if resetSession {
            queue = []
            requestedPages = [:]
            totalPages = [:]
        }

        do {
            try await ensureGenresLoaded()
            let excluded = try LibraryRepository.excludedKeys(in: context)
            let types = appliedFilter.mediaType.map { [$0] }
                ?? MediaType.allCases

            var candidates: [MediaItem] = []
            var pageMetadata: [(MediaType, Int, Int)] = []
            try await withThrowingTaskGroup(
                of: (MediaType, Int, TMDBPage).self
            ) {
                group in
                for type in types {
                    let filter = appliedFilter
                    group.addTask { [service] in
                        let first = try await service.discover(
                            type: type,
                            filter: filter,
                            page: 1
                        )
                        let randomPage = Int.random(
                            in: 1...max(first.totalPages, 1)
                        )
                        if randomPage == 1 {
                            return (type, randomPage, first)
                        }
                        let random = try await service.discover(
                            type: type,
                            filter: filter,
                            page: randomPage
                        )
                        return (type, randomPage, random)
                    }
                }

                for try await (type, requestedPage, page) in group {
                    pageMetadata.append(
                        (type, requestedPage, page.totalPages)
                    )
                    candidates.append(contentsOf: page.items)
                }
            }

            guard loadGeneration == generation else { return }
            for (type, requestedPage, maximumPage) in pageMetadata {
                totalPages[type] = maximumPage
                requestedPages[type, default: []].insert(1)
                requestedPages[type, default: []].insert(requestedPage)
            }
            queue = prepared(candidates, excluding: excluded)
            preloadUpcomingPosters()
        } catch {
            if loadGeneration == generation {
                errorMessage = error.localizedDescription
            }
        }

        if loadGeneration == generation {
            isLoading = false
        }
    }

    func refillIfNeeded(in context: ModelContext) async {
        guard queue.count < 5, !isLoading, !isRefilling else { return }
        let generation = loadGeneration
        isRefilling = true

        do {
            let excluded = try LibraryRepository.excludedKeys(in: context)
                .union(queue.map(\.id))
            let types = appliedFilter.mediaType.map { [$0] }
                ?? MediaType.allCases.shuffled()
            var candidates: [MediaItem] = []
            var pageMetadata: [(MediaType, Int, Int)] = []

            for type in types {
                guard let page = nextPage(for: type) else { continue }
                let response = try await service.discover(
                    type: type,
                    filter: appliedFilter,
                    page: page
                )
                pageMetadata.append((type, page, response.totalPages))
                candidates.append(contentsOf: response.items)
            }

            guard loadGeneration == generation else {
                isRefilling = false
                return
            }
            for (type, page, maximumPage) in pageMetadata {
                totalPages[type] = maximumPage
                requestedPages[type, default: []].insert(page)
            }
            queue.append(contentsOf: prepared(candidates, excluding: excluded))
            preloadUpcomingPosters()
        } catch {
            if loadGeneration == generation, queue.isEmpty {
                errorMessage = error.localizedDescription
            }
        }

        isRefilling = false
    }

    func perform(
        _ action: CardAction,
        on media: MediaItem,
        in context: ModelContext
    ) async -> Bool {
        guard !isCommittingAction, queue.first?.id == media.id else {
            return false
        }
        isCommittingAction = true

        do {
            switch action {
            case .skip:
                try LibraryRepository.skip(media, in: context)
            case .wantToWatch:
                try LibraryRepository.save(
                    media,
                    as: .wantToWatch,
                    in: context
                )
            case .watched:
                try LibraryRepository.save(media, as: .watched, in: context)
            }

            queue.removeAll { $0.id == media.id }
            feedbackTrigger += 1
            isCommittingAction = false
            await refillIfNeeded(in: context)
            return true
        } catch {
            alertMessage = "保存失败，卡片没有移动，请重试。"
            isCommittingAction = false
            return false
        }
    }

    func apply(_ filter: DiscoverFilter, in context: ModelContext) async {
        guard filter.isValid else { return }
        appliedFilter = filter
        saveFilter()
        await loadDiscover(in: context, resetSession: true)
    }

    func resetFilter(in context: ModelContext) async {
        appliedFilter = .default
        saveFilter()
        await loadDiscover(in: context, resetSession: true)
    }

    func move(
        _ item: LibraryItem,
        to status: LibraryStatus,
        in context: ModelContext
    ) {
        do {
            try LibraryRepository.move(item, to: status, in: context)
            feedbackTrigger += 1
        } catch {
            alertMessage = "状态更新失败，作品仍保留在原列表。"
        }
    }

    func delete(_ item: LibraryItem, in context: ModelContext) {
        do {
            try LibraryRepository.delete(item, in: context)
        } catch {
            alertMessage = "删除失败，请稍后重试。"
        }
    }

    func refreshMetadata(
        for items: [LibraryItem],
        in context: ModelContext
    ) async {
        guard isAPIConfigured else { return }
        let refreshCutoff = Date.now.addingTimeInterval(-24 * 60 * 60)
        let staleItems = items.filter {
            ($0.lastRefreshedAt ?? .distantPast) < refreshCutoff
        }

        for item in staleItems.prefix(20) {
            do {
                let media = try await service.details(
                    type: item.mediaType,
                    id: item.tmdbID
                )
                item.refresh(with: media)
                try context.save()
            } catch {
                context.rollback()
                continue
            }
        }
    }

    private func ensureGenresLoaded() async throws {
        for type in MediaType.allCases where genres[type] == nil {
            genres[type] = try await service.genres(for: type)
        }
    }

    private func prepared(
        _ candidates: [MediaItem],
        excluding excluded: Set<String>
    ) -> [MediaItem] {
        var seen = excluded
        return candidates.shuffled().compactMap { item in
            guard item.posterPath != nil, seen.insert(item.id).inserted else {
                return nil
            }
            var decorated = item
            let lookup = Dictionary(
                uniqueKeysWithValues: (genres[item.mediaType] ?? []).map {
                    ($0.id, $0.name)
                }
            )
            decorated.genreNames = item.genreIDs.compactMap { lookup[$0] }
            return decorated
        }
    }

    private func nextPage(for type: MediaType) -> Int? {
        let maximum = max(totalPages[type] ?? 1, 1)
        let requested = requestedPages[type, default: []]
        let available = (1...maximum).filter { !requested.contains($0) }
        return available.randomElement()
    }

    private func preloadUpcomingPosters() {
        for media in queue.dropFirst().prefix(3) {
            guard let url = media.posterURL() else { continue }
            Task.detached(priority: .utility) {
                _ = try? await URLSession.shared.data(from: url)
            }
        }
    }

    private func saveFilter() {
        guard let data = try? JSONEncoder().encode(appliedFilter) else {
            return
        }
        defaults.set(data, forKey: filterKey)
    }

    private static func loadFilter(from defaults: UserDefaults) -> DiscoverFilter {
        guard
            let data = defaults.data(forKey: "CineSwipe.appliedFilter"),
            let filter = try? JSONDecoder().decode(
                DiscoverFilter.self,
                from: data
            )
        else {
            return .default
        }
        return filter
    }
}
