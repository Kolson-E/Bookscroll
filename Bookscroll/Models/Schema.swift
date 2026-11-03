import Foundation
import SwiftData

/// Version 1 of the library schema: the models as they are now.
///
/// To change a model later:
/// 1. Copy the current `Book`, `Segment` and `Mark` definitions into this enum as nested
///    types, so version 1 stays frozen.
/// 2. Add `BookscrollSchemaV2` with the changed models and append it to
///    `BookscrollMigrationPlan.schemas`.
/// 3. Add a lightweight or custom `MigrationStage` from V1 to V2, and a test that opens a
///    V1 store with the plan.
enum BookscrollSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Book.self, Segment.self, Mark.self]
    }
}

enum BookscrollMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BookscrollSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum LibraryContainer {
    static var schema: Schema { Schema(versionedSchema: BookscrollSchemaV1.self) }

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
