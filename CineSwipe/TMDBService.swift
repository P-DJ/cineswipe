import Foundation

nonisolated enum TMDBError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int)
    case decodingFailed
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "尚未配置 TMDB API Key。请在运行环境中设置 TMDB_API_KEY。"
        case .invalidResponse:
            "TMDB 返回了无法识别的响应。"
        case .httpStatus(401):
            "TMDB API Key 无效，请检查本地配置。"
        case .httpStatus(429):
            "请求有点频繁，请稍后再试。"
        case .httpStatus:
            "TMDB 暂时无法响应，请稍后再试。"
        case .decodingFailed:
            "影视数据解析失败，请稍后再试。"
        case .networkUnavailable:
            "网络好像去看电影了，连接后再试试。"
        }
    }
}

nonisolated struct TMDBPage: Sendable {
    let items: [MediaItem]
    let totalPages: Int
}

actor TMDBService {
    private let baseURL = URL(string: "https://api.themoviedb.org/3")!
    private let session: URLSession
    private let apiKey: String

    init(apiKey: String = TMDBService.configuredAPIKey) {
        self.apiKey = apiKey
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = .shared
        configuration.requestCachePolicy = .useProtocolCachePolicy
        session = URLSession(configuration: configuration)
    }

    nonisolated static var configuredAPIKey: String {
        let environmentKey = ProcessInfo.processInfo.environment[
            "TMDB_API_KEY"
        ]
        let bundleKey = Bundle.main.object(
            forInfoDictionaryKey: "TMDB_API_KEY"
        ) as? String
        let candidate = environmentKey ?? bundleKey ?? ""
        guard !candidate.hasPrefix("$(") else { return "" }
        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static var isConfigured: Bool {
        !configuredAPIKey.isEmpty
    }

    func genres(for type: MediaType) async throws -> [GenreOption] {
        let response: GenreResponse = try await request(
            path: "genre/\(type.rawValue)/list",
            queryItems: []
        )
        return response.genres
    }

    func discover(
        type: MediaType,
        filter: DiscoverFilter,
        page: Int
    ) async throws -> TMDBPage {
        let response: DiscoverResponse = try await request(
            path: "discover/\(type.rawValue)",
            queryItems: discoverQuery(
                type: type,
                filter: filter,
                page: page
            )
        )

        let items = response.results.compactMap {
            $0.mediaItem(type: type)
        }
        return TMDBPage(
            items: items,
            totalPages: min(max(response.totalPages, 1), 500)
        )
    }

    func details(type: MediaType, id: Int) async throws -> MediaItem {
        let response: DetailResponse = try await request(
            path: "\(type.rawValue)/\(id)",
            queryItems: []
        )
        guard let item = response.mediaItem(type: type) else {
            throw TMDBError.decodingFailed
        }
        return item
    }

    private func discoverQuery(
        type: MediaType,
        filter: DiscoverFilter,
        page: Int
    ) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "vote_count.gte", value: "100")
        ]

        if type == .movie {
            items.append(URLQueryItem(name: "include_adult", value: "false"))
        }

        if !filter.genreIDs.isEmpty {
            let value = filter.genreIDs.map(String.init).joined(separator: ",")
            items.append(URLQueryItem(name: "with_genres", value: value))
        }

        if !filter.regions.isEmpty {
            items.append(
                URLQueryItem(
                    name: "with_origin_country",
                    value: filter.regions.joined(separator: "|")
                )
            )
        }

        appendDateRange(type: type, filter: filter, to: &items)

        if let minimumRating = filter.minimumRating {
            items.append(
                URLQueryItem(
                    name: "vote_average.gte",
                    value: String(format: "%.1f", minimumRating)
                )
            )
        }

        return items
    }

    private func appendDateRange(
        type: MediaType,
        filter: DiscoverFilter,
        to items: inout [URLQueryItem]
    ) {
        let prefix = type == .movie ? "primary_release_date" : "first_air_date"
        let currentYear = Calendar.current.component(.year, from: .now)

        if let startYear = filter.startYear {
            items.append(
                URLQueryItem(
                    name: "\(prefix).gte",
                    value: "\(startYear)-01-01"
                )
            )
        }

        let endYear = min(filter.endYear ?? currentYear, currentYear)
        items.append(
            URLQueryItem(
                name: "\(prefix).lte",
                value: "\(endYear)-12-31"
            )
        )
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> Response {
        guard !apiKey.isEmpty else { throw TMDBError.missingAPIKey }

        var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = queryItems + [
            URLQueryItem(name: "language", value: "zh-CN"),
            URLQueryItem(name: "api_key", value: apiKey)
        ]

        guard let url = components.url else {
            throw TMDBError.invalidResponse
        }

        let data = try await responseData(for: URLRequest(url: url))
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw TMDBError.decodingFailed
        }
    }

    private func responseData(
        for request: URLRequest,
        retrying: Bool = false
    ) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw TMDBError.invalidResponse
            }

            let isRecoverableStatus = response.statusCode == 429
                || (500...599).contains(response.statusCode)
            if isRecoverableStatus, !retrying {
                try await Task.sleep(for: .milliseconds(350))
                return try await responseData(for: request, retrying: true)
            }

            guard (200...299).contains(response.statusCode) else {
                throw TMDBError.httpStatus(response.statusCode)
            }
            return data
        } catch let error as URLError {
            guard error.code != .cancelled else { throw error }
            if !retrying {
                try await Task.sleep(for: .milliseconds(350))
                return try await responseData(for: request, retrying: true)
            }
            throw TMDBError.networkUnavailable
        }
    }
}

nonisolated private struct DiscoverResponse: Decodable {
    let results: [DiscoverDTO]
    let totalPages: Int

    enum CodingKeys: String, CodingKey {
        case results
        case totalPages = "total_pages"
    }
}

nonisolated private struct GenreResponse: Decodable {
    let genres: [GenreOption]
}

nonisolated private struct DiscoverDTO: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let originalTitle: String?
    let originalName: String?
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let genreIDs: [Int]

    enum CodingKeys: String, CodingKey {
        case id, title, name
        case originalTitle = "original_title"
        case originalName = "original_name"
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case genreIDs = "genre_ids"
    }

    func mediaItem(type: MediaType) -> MediaItem? {
        guard posterPath != nil else { return nil }
        let localized = title ?? name ?? originalTitle ?? originalName ?? ""
        guard !localized.isEmpty else { return nil }
        let date = type == .movie ? releaseDate : firstAirDate
        return MediaItem(
            tmdbID: id,
            mediaType: type,
            localizedTitle: localized,
            originalTitle: originalTitle ?? originalName,
            posterPath: posterPath,
            releaseYear: date.flatMap(Self.year(from:)),
            tmdbRating: voteAverage,
            genreIDs: genreIDs,
            genreNames: []
        )
    }

    private static func year(from date: String) -> Int? {
        Int(date.prefix(4))
    }
}

nonisolated private struct DetailResponse: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let originalTitle: String?
    let originalName: String?
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let genres: [GenreOption]

    enum CodingKeys: String, CodingKey {
        case id, title, name, genres
        case originalTitle = "original_title"
        case originalName = "original_name"
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
    }

    func mediaItem(type: MediaType) -> MediaItem? {
        let localized = title ?? name ?? originalTitle ?? originalName ?? ""
        guard !localized.isEmpty else { return nil }
        let date = type == .movie ? releaseDate : firstAirDate
        return MediaItem(
            tmdbID: id,
            mediaType: type,
            localizedTitle: localized,
            originalTitle: originalTitle ?? originalName,
            posterPath: posterPath,
            releaseYear: date.flatMap { Int($0.prefix(4)) },
            tmdbRating: voteAverage,
            genreIDs: genres.map(\.id),
            genreNames: genres.map(\.name)
        )
    }
}
