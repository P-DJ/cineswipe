import Foundation
import SwiftData

@Model
final class LibraryItem {
    @Attribute(.unique) var key: String
    var tmdbID: Int
    var mediaTypeRawValue: String
    var statusRawValue: String
    var localizedTitle: String
    var originalTitle: String?
    var posterPath: String?
    var releaseYear: Int?
    var tmdbRating: Double?
    var genreIDs: [Int]
    var createdAt: Date
    var updatedAt: Date
    var lastRefreshedAt: Date?

    init(media: MediaItem, status: LibraryStatus, now: Date = .now) {
        key = media.id
        tmdbID = media.tmdbID
        mediaTypeRawValue = media.mediaType.rawValue
        statusRawValue = status.rawValue
        localizedTitle = media.localizedTitle
        originalTitle = media.originalTitle
        posterPath = media.posterPath
        releaseYear = media.releaseYear
        tmdbRating = media.tmdbRating
        genreIDs = media.genreIDs
        createdAt = now
        updatedAt = now
    }

    var mediaType: MediaType {
        MediaType(rawValue: mediaTypeRawValue) ?? .movie
    }

    var status: LibraryStatus {
        get { LibraryStatus(rawValue: statusRawValue) ?? .wantToWatch }
        set { statusRawValue = newValue.rawValue }
    }

    var media: MediaItem {
        MediaItem(
            tmdbID: tmdbID,
            mediaType: mediaType,
            localizedTitle: localizedTitle,
            originalTitle: originalTitle,
            posterPath: posterPath,
            releaseYear: releaseYear,
            tmdbRating: tmdbRating,
            genreIDs: genreIDs,
            genreNames: []
        )
    }

    func move(to newStatus: LibraryStatus, now: Date = .now) {
        status = newStatus
        createdAt = now
        updatedAt = now
    }

    func refresh(with media: MediaItem, now: Date = .now) {
        localizedTitle = media.localizedTitle
        originalTitle = media.originalTitle ?? originalTitle
        posterPath = media.posterPath ?? posterPath
        releaseYear = media.releaseYear ?? releaseYear
        tmdbRating = media.tmdbRating ?? tmdbRating
        if !media.genreIDs.isEmpty {
            genreIDs = media.genreIDs
        }
        lastRefreshedAt = now
    }
}

@Model
final class SkippedItem {
    @Attribute(.unique) var key: String
    var tmdbID: Int
    var mediaTypeRawValue: String
    var skippedAt: Date
    var expiresAt: Date

    init(media: MediaItem, now: Date = .now) {
        key = media.id
        tmdbID = media.tmdbID
        mediaTypeRawValue = media.mediaType.rawValue
        skippedAt = now
        expiresAt = Calendar.current.date(
            byAdding: .day,
            value: 30,
            to: now
        ) ?? now.addingTimeInterval(30 * 24 * 60 * 60)
    }
}

@MainActor
enum LibraryRepository {
    static func excludedKeys(in context: ModelContext) throws -> Set<String> {
        try cleanExpiredSkips(in: context)
        let library = try context.fetch(FetchDescriptor<LibraryItem>())
        let skipped = try context.fetch(FetchDescriptor<SkippedItem>())
        return Set(library.map(\.key) + skipped.map(\.key))
    }

    static func save(
        _ media: MediaItem,
        as status: LibraryStatus,
        in context: ModelContext
    ) throws {
        let items = try context.fetch(FetchDescriptor<LibraryItem>())
        let now = Date.now

        if let existing = items.first(where: { $0.key == media.id }) {
            existing.refresh(with: media, now: now)
            existing.move(to: status, now: now)
        } else {
            context.insert(LibraryItem(media: media, status: status, now: now))
        }

        try commit(context)
    }

    static func skip(_ media: MediaItem, in context: ModelContext) throws {
        let skipped = try context.fetch(FetchDescriptor<SkippedItem>())
        if let existing = skipped.first(where: { $0.key == media.id }) {
            let now = Date.now
            existing.skippedAt = now
            existing.expiresAt = Calendar.current.date(
                byAdding: .day,
                value: 30,
                to: now
            ) ?? now.addingTimeInterval(30 * 24 * 60 * 60)
        } else {
            context.insert(SkippedItem(media: media))
        }
        try commit(context)
    }

    static func move(
        _ item: LibraryItem,
        to status: LibraryStatus,
        in context: ModelContext
    ) throws {
        item.move(to: status)
        try commit(context)
    }

    static func delete(_ item: LibraryItem, in context: ModelContext) throws {
        context.delete(item)
        try commit(context)
    }

    static func cleanExpiredSkips(in context: ModelContext) throws {
        let skipped = try context.fetch(FetchDescriptor<SkippedItem>())
        let expired = skipped.filter { $0.expiresAt <= .now }
        guard !expired.isEmpty else { return }
        expired.forEach(context.delete)
        try commit(context)
    }

    private static func commit(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
