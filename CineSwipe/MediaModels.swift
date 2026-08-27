import Foundation

nonisolated enum MediaType: String, Codable, CaseIterable, Identifiable,
    Sendable {
    case movie
    case tv

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .movie: "电影"
        case .tv: "电视剧"
        }
    }
}

nonisolated enum LibraryStatus: String, Codable, Sendable {
    case wantToWatch
    case watched

    var title: String {
        switch self {
        case .wantToWatch: "想看"
        case .watched: "已看"
        }
    }
}

nonisolated struct GenreOption: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
}

nonisolated struct MediaItem: Codable, Hashable, Identifiable, Sendable {
    let tmdbID: Int
    let mediaType: MediaType
    let localizedTitle: String
    let originalTitle: String?
    let posterPath: String?
    let releaseYear: Int?
    let tmdbRating: Double?
    let genreIDs: [Int]
    var genreNames: [String]

    var id: String { "\(mediaType.rawValue)-\(tmdbID)" }

    var ratingText: String {
        guard let tmdbRating, tmdbRating > 0 else {
            return "暂无评分"
        }
        return String(format: "%.1f", tmdbRating)
    }

    func posterURL(width: Int = 780) -> URL? {
        guard let posterPath else { return nil }
        return URL(
            string: "https://image.tmdb.org/t/p/w\(width)\(posterPath)"
        )
    }
}

nonisolated struct DiscoverFilter: Codable, Equatable, Sendable {
    var mediaType: MediaType?
    var genreIDs: [Int] = []
    var regions: [String] = []
    var startYear: Int?
    var endYear: Int?
    var minimumRating: Double?

    static let `default` = DiscoverFilter()

    var isDefault: Bool {
        mediaType == nil
            && genreIDs.isEmpty
            && regions.isEmpty
            && startYear == nil
            && endYear == nil
            && minimumRating == nil
    }

    var isValid: Bool {
        guard mediaType != nil else { return false }
        guard let startYear, let endYear else { return true }
        return startYear <= endYear
    }

    mutating func selectMediaType(_ newType: MediaType?) {
        guard mediaType != newType else { return }
        mediaType = newType
        genreIDs = []
        regions = []
        startYear = nil
        endYear = nil
        minimumRating = nil
    }
}

nonisolated enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case discover
    case wantToWatch
    case watched

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: "发现"
        case .wantToWatch: "想看"
        case .watched: "已看"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "sparkles.tv"
        case .wantToWatch: "bookmark"
        case .watched: "checkmark.circle"
        }
    }
}

nonisolated enum CardAction: Equatable, Sendable {
    case skip
    case wantToWatch
    case watched

    var title: String {
        switch self {
        case .skip: "跳过"
        case .wantToWatch: "想看"
        case .watched: "已看"
        }
    }

    var systemImage: String {
        switch self {
        case .skip: "xmark"
        case .wantToWatch: "bookmark.fill"
        case .watched: "checkmark"
        }
    }
}
