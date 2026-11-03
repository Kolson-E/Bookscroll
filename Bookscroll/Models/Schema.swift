import Foundation
import SwiftData

/// Version 1: the first released models, frozen here so the migration plan can recognise
/// a version 1 library. Never change these copies.
enum BookscrollSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Book.self, Segment.self, Mark.self]
    }
}

extension BookscrollSchemaV1 {
    @Model
    final class Book {
        @Attribute(.unique) var id: UUID
        /// Small integer assigned at import. It prefixes the segment keys of this book.
        var ordinal: Int
        var title: String
        var author: String
        var formatRaw: String
        var addedAt: Date
        /// Length of the normalized text in UTF-16 code units. All offsets use the same unit.
        var totalCharacters: Int
        /// Reading position as an offset into the normalized text (not a post index).
        var positionOffset: Int
        /// True when paragraph detection failed (PDF paragraphs average over 300 words)
        /// and the book always shows Passages style.
        var passagesOnly: Bool
        var paragraphSegmentCount: Int
        var passageSegmentCount: Int
        var importNote: String?
        /// Set when the user deletes the book. The book is hidden at once and its rows are
        /// removed in the background; a deletion cut short (the app was closed) resumes at launch.
        var deletionPending: Bool = false
        @Relationship(deleteRule: .cascade, inverse: \Segment.book) var segments: [Segment]? = []
        @Relationship(deleteRule: .cascade, inverse: \Mark.book) var marks: [Mark]? = []

        init(
            id: UUID = UUID(),
            ordinal: Int,
            title: String,
            author: String,
            format: BookFormat,
            addedAt: Date = .now,
            totalCharacters: Int,
            positionOffset: Int = 0,
            passagesOnly: Bool,
            paragraphSegmentCount: Int,
            passageSegmentCount: Int,
            importNote: String?
        ) {
            self.id = id
            self.ordinal = ordinal
            self.title = title
            self.author = author
            self.formatRaw = format.rawValue
            self.addedAt = addedAt
            self.totalCharacters = totalCharacters
            self.positionOffset = positionOffset
            self.passagesOnly = passagesOnly
            self.paragraphSegmentCount = paragraphSegmentCount
            self.passageSegmentCount = passageSegmentCount
            self.importNote = importNote
        }

        var format: BookFormat { BookFormat(rawValue: formatRaw) ?? .epub }

        var progress: Double {
            guard totalCharacters > 0 else { return 0 }
            return min(1, max(0, Double(positionOffset) / Double(totalCharacters)))
        }
    }

    @Model
    final class Segment {
        var bookID: UUID
        var styleRaw: Int
        var index: Int
        var charStart: Int
        var charEnd: Int
        var chapter: String
        var text: String
        @Attribute(.unique) var indexKey: Int64
        @Attribute(.unique) var offsetKey: Int64
        var book: Book?

        init(bookID: UUID, ordinal: Int, draft: SegmentDraft) {
            self.bookID = bookID
            self.styleRaw = draft.style.storageValue
            self.index = draft.index
            self.charStart = draft.charStart
            self.charEnd = draft.charEnd
            self.chapter = draft.chapter
            self.text = draft.text
            self.indexKey = SegmentKey.make(ordinal: ordinal, style: draft.style, value: draft.index)
            self.offsetKey = SegmentKey.make(ordinal: ordinal, style: draft.style, value: draft.charStart)
        }

        var style: PostStyle { PostStyle(storageValue: styleRaw) }
    }

    @Model
    final class Mark {
        @Attribute(.unique) var id: UUID
        var bookID: UUID
        var kindRaw: String
        var charStart: Int
        var charEnd: Int
        var createdAt: Date
        var book: Book?

        init(id: UUID = UUID(), bookID: UUID, kind: MarkKind, charStart: Int, charEnd: Int, createdAt: Date = .now) {
            self.id = id
            self.bookID = bookID
            self.kindRaw = kind.rawValue
            self.charStart = charStart
            self.charEnd = charEnd
            self.createdAt = createdAt
        }

        var kind: MarkKind { MarkKind(rawValue: kindRaw) ?? .like }
    }
}

/// Version 2: feed filters (hide from Mix, snooze, weight), the automatic word limit and the
/// chapter table on `Book`. The models are the live ones in Models.swift.
///
/// To change a model later:
/// 1. Copy the current `Book`, `Segment` and `Mark` into an extension of this enum, as
///    version 1 is copied above, so version 2 stays frozen.
/// 2. Add `BookscrollSchemaV3` with the live models and append it to the plan.
/// 3. Add a migration stage from V2 to V3 and a test that opens a V2 store.
enum BookscrollSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Book.self, Segment.self, Mark.self]
    }
}

enum BookscrollMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BookscrollSchemaV1.self, BookscrollSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [v1ToV2]
    }

    /// Only new attributes with default values. Values that depend on the text (word limit,
    /// chapter table) are filled in the background after launch (`DerivedDataBackfill`).
    static let v1ToV2 = MigrationStage.lightweight(fromVersion: BookscrollSchemaV1.self, toVersion: BookscrollSchemaV2.self)
}

enum LibraryContainer {
    static var schema: Schema { Schema(versionedSchema: BookscrollSchemaV2.self) }

    /// Opens a library with the migration plan. `url` nil means the default on-disk store.
    static func make(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let url {
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: schema)
        }
        return try ModelContainer(for: schema, migrationPlan: BookscrollMigrationPlan.self, configurations: configuration)
    }
}
