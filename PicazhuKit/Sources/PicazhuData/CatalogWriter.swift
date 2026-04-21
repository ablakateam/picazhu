import Foundation
import GRDB
import PicazhuCore

public actor CatalogWriter {
    private let db: DatabaseWriter

    public init(catalog: Catalog) {
        self.db = catalog.writer
    }

    public func insertWatchedRoot(displayName: String, bookmark: Data) async throws -> WatchedRootID {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO watched_roots (display_name, bookmark, access_state, created_at)
                    VALUES (?, ?, 'ok', ?)
                """,
                arguments: [displayName, bookmark, Date().timeIntervalSince1970]
            )
            return WatchedRootID(rawValue: db.lastInsertedRowID)
        }
    }

    public func deleteWatchedRoot(_ id: WatchedRootID) async throws {
        try await db.write { db in
            try db.execute(sql: "DELETE FROM watched_roots WHERE id = ?", arguments: [id.rawValue])
        }
    }

    public func updateRootAccessState(_ id: WatchedRootID, _ state: RootAccessState) async throws {
        try await db.write { db in
            try db.execute(
                sql: "UPDATE watched_roots SET access_state = ? WHERE id = ?",
                arguments: [state.rawValue, id.rawValue]
            )
        }
    }

    public func markRootScanned(_ id: WatchedRootID, at date: Date = Date()) async throws {
        try await db.write { db in
            try db.execute(
                sql: "UPDATE watched_roots SET last_scan_at = ? WHERE id = ?",
                arguments: [date.timeIntervalSince1970, id.rawValue]
            )
        }
    }

    public func upsertFolder(
        rootID: WatchedRootID,
        parentID: FolderID?,
        relativePath: String,
        name: String,
        depth: Int
    ) async throws -> FolderID {
        try await db.write { db in
            if let row = try Row.fetchOne(
                db,
                sql: "SELECT id, parent_id, depth FROM folders WHERE root_id = ? AND relative_path = ?",
                arguments: [rootID.rawValue, relativePath]
            ) {
                let existingID = FolderID(rawValue: row["id"])
                let existingParent: Int64? = row["parent_id"]
                let existingDepth: Int = row["depth"]
                if existingParent != parentID?.rawValue || existingDepth != depth {
                    try db.execute(
                        sql: "UPDATE folders SET parent_id = ?, depth = ?, name = ? WHERE id = ?",
                        arguments: [parentID?.rawValue, depth, name, existingID.rawValue] as StatementArguments
                    )
                }
                return existingID
            }
            let args: StatementArguments = [
                rootID.rawValue,
                parentID?.rawValue,
                relativePath,
                name,
                depth
            ]
            try db.execute(
                sql: """
                    INSERT INTO folders (root_id, parent_id, relative_path, name, depth)
                    VALUES (?, ?, ?, ?, ?)
                """,
                arguments: args
            )
            return FolderID(rawValue: db.lastInsertedRowID)
        }
    }

    public func insertMediaDrafts(_ drafts: [MediaItemDraft], folderID: FolderID) async throws {
        guard !drafts.isEmpty else { return }
        try await db.write { db in
            let now = Date().timeIntervalSince1970
            for d in drafts {
                let args: StatementArguments = [
                    folderID.rawValue,
                    d.rootID.rawValue,
                    d.filename,
                    d.relativePath,
                    d.fileExtension,
                    d.kind.rawValue,
                    d.size,
                    d.createdAt?.timeIntervalSince1970,
                    d.modifiedAt.timeIntervalSince1970,
                    now
                ]
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO media_items (
                            folder_id, root_id, filename, relative_path, extension, kind,
                            size, created_at, modified_at,
                            thumb_state, meta_state, ai_state, indexed_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 'pending', 'none', ?)
                    """,
                    arguments: args
                )
            }
            try db.execute(
                sql: """
                    UPDATE folders
                    SET item_count = (SELECT COUNT(*) FROM media_items WHERE folder_id = ?)
                    WHERE id = ?
                """,
                arguments: [folderID.rawValue, folderID.rawValue]
            )
        }
    }

    public func setMediaState(
        _ id: MediaItemID,
        thumb: LifecycleState? = nil,
        meta: LifecycleState? = nil
    ) async throws {
        try await db.write { db in
            if let t = thumb {
                try db.execute(
                    sql: "UPDATE media_items SET thumb_state = ? WHERE id = ?",
                    arguments: [t.rawValue, id.rawValue]
                )
            }
            if let me = meta {
                try db.execute(
                    sql: "UPDATE media_items SET meta_state = ? WHERE id = ?",
                    arguments: [me.rawValue, id.rawValue]
                )
            }
        }
    }

    public func updateMediaDimensions(
        _ id: MediaItemID,
        width: Int?,
        height: Int?,
        duration: Double?,
        orientation: Int?
    ) async throws {
        try await db.write { db in
            let args: StatementArguments = [width, height, duration, orientation, id.rawValue]
            try db.execute(
                sql: """
                    UPDATE media_items
                    SET width = ?, height = ?, duration = ?, orientation = ?
                    WHERE id = ?
                """,
                arguments: args
            )
        }
    }

    public func upsertMetadata(
        itemID: MediaItemID,
        exifJSON: String?,
        cameraMake: String?,
        cameraModel: String?,
        lens: String?,
        iso: Int?,
        fNumber: Double?,
        exposureTime: Double?,
        focalLength: Double?,
        captureTime: Date?,
        gpsLat: Double?,
        gpsLon: Double?,
        codec: String?
    ) async throws {
        try await db.write { db in
            let args: StatementArguments = [
                itemID.rawValue,
                exifJSON,
                cameraMake,
                cameraModel,
                lens,
                iso,
                fNumber,
                exposureTime,
                focalLength,
                captureTime?.timeIntervalSince1970,
                gpsLat,
                gpsLon,
                codec
            ]
            try db.execute(
                sql: """
                    INSERT INTO metadata (
                        item_id, exif_json, camera_make, camera_model, lens,
                        iso, f_number, exposure_time, focal_length, capture_time,
                        gps_lat, gps_lon, codec
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(item_id) DO UPDATE SET
                        exif_json = excluded.exif_json,
                        camera_make = excluded.camera_make,
                        camera_model = excluded.camera_model,
                        lens = excluded.lens,
                        iso = excluded.iso,
                        f_number = excluded.f_number,
                        exposure_time = excluded.exposure_time,
                        focal_length = excluded.focal_length,
                        capture_time = excluded.capture_time,
                        gps_lat = excluded.gps_lat,
                        gps_lon = excluded.gps_lon,
                        codec = excluded.codec
                """,
                arguments: args
            )
        }
    }

    public func insertThumbnailRecord(
        itemID: MediaItemID,
        cacheKey: String,
        pixelSize: Int
    ) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO thumbnails (item_id, cache_key, pixel_size, generated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(item_id) DO UPDATE SET
                        cache_key = excluded.cache_key,
                        pixel_size = excluded.pixel_size,
                        generated_at = excluded.generated_at
                """,
                arguments: [itemID.rawValue, cacheKey, pixelSize, Date().timeIntervalSince1970]
            )
        }
    }

    public func insertFTSRow(
        itemID: MediaItemID,
        filename: String,
        folderPath: String,
        caption: String? = nil,
        tags: String? = nil,
        ocr: String? = nil
    ) async throws {
        try await db.write { db in
            try db.execute(sql: "DELETE FROM media_fts WHERE rowid = ?", arguments: [itemID.rawValue])
            try db.execute(
                sql: """
                    INSERT INTO media_fts (rowid, filename, folder_path, caption, tags, ocr)
                    VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    itemID.rawValue,
                    filename,
                    folderPath,
                    caption ?? "",
                    tags ?? "",
                    ocr ?? ""
                ]
            )
        }
    }

    public func pinFolder(_ id: FolderID) async throws {
        try await db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO pinned_folders (folder_id, pinned_at) VALUES (?, ?)",
                arguments: [id.rawValue, Date().timeIntervalSince1970]
            )
        }
    }

    public func unpinFolder(_ id: FolderID) async throws {
        try await db.write { db in
            try db.execute(sql: "DELETE FROM pinned_folders WHERE folder_id = ?", arguments: [id.rawValue])
        }
    }

    public func recordRecentFolder(_ id: FolderID) async throws {
        try await db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO recent_folders (folder_id, visited_at) VALUES (?, ?)",
                arguments: [id.rawValue, Date().timeIntervalSince1970]
            )
        }
    }

    public func upsertAIProvider(kind: String, name: String, configJSON: String, enabled: Bool) async throws -> Int64 {
        try await db.write { db in
            if let row = try Row.fetchOne(
                db,
                sql: "SELECT id FROM ai_providers WHERE name = ?",
                arguments: [name]
            ) {
                let id: Int64 = row["id"]
                try db.execute(
                    sql: "UPDATE ai_providers SET kind = ?, config_json = ?, enabled = ? WHERE id = ?",
                    arguments: [kind, configJSON, enabled ? 1 : 0, id] as StatementArguments
                )
                return id
            }
            try db.execute(
                sql: """
                    INSERT INTO ai_providers (kind, name, config_json, enabled, created_at)
                    VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [kind, name, configJSON, enabled ? 1 : 0, Date().timeIntervalSince1970] as StatementArguments
            )
            return db.lastInsertedRowID
        }
    }

    public func enqueueAIJobs(itemIDs: [MediaItemID]) async throws {
        guard !itemIDs.isEmpty else { return }
        try await db.write { db in
            let now = Date().timeIntervalSince1970
            for id in itemIDs {
                try db.execute(
                    sql: """
                        INSERT INTO jobs (kind, target_id, state, enqueued_at, updated_at)
                        VALUES ('ai', ?, 'queued', ?, ?)
                    """,
                    arguments: [id.rawValue, now, now] as StatementArguments
                )
                try db.execute(
                    sql: "UPDATE media_items SET ai_state = 'pending' WHERE id = ?",
                    arguments: [id.rawValue]
                )
            }
        }
    }

    public func nextAIJob() async throws -> (jobID: Int64, itemID: MediaItemID)? {
        try await db.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, target_id FROM jobs
                    WHERE kind = 'ai' AND state = 'queued'
                    ORDER BY enqueued_at ASC
                    LIMIT 1
                """
            ) else { return nil }
            let jobID: Int64 = row["id"]
            let targetID: Int64 = row["target_id"]
            try db.execute(
                sql: "UPDATE jobs SET state = 'running', updated_at = ? WHERE id = ?",
                arguments: [Date().timeIntervalSince1970, jobID] as StatementArguments
            )
            return (jobID, MediaItemID(rawValue: targetID))
        }
    }

    public func completeAIJob(_ jobID: Int64, success: Bool, error: String? = nil) async throws {
        try await db.write { db in
            try db.execute(
                sql: "UPDATE jobs SET state = ?, error = ?, updated_at = ? WHERE id = ?",
                arguments: [
                    success ? "done" : "failed",
                    error,
                    Date().timeIntervalSince1970,
                    jobID
                ] as StatementArguments
            )
        }
    }

    public func setItemAIState(_ id: MediaItemID, _ state: AIState) async throws {
        try await db.write { db in
            try db.execute(
                sql: "UPDATE media_items SET ai_state = ? WHERE id = ?",
                arguments: [state.rawValue, id.rawValue]
            )
        }
    }

    public func writeAIEnrichment(
        itemID: MediaItemID,
        providerID: Int64?,
        modelVersion: String?,
        caption: String?,
        tagsJSON: String?,
        objectsJSON: String?,
        scene: String?,
        ocrText: String?,
        confidence: Double?
    ) async throws {
        try await db.write { db in
            let args: StatementArguments = [
                itemID.rawValue,
                providerID,
                modelVersion,
                caption,
                tagsJSON,
                objectsJSON,
                scene,
                ocrText,
                confidence,
                Date().timeIntervalSince1970
            ]
            try db.execute(
                sql: """
                    INSERT INTO ai_enrichment (
                        item_id, provider_id, model_version,
                        caption, tags_json, objects_json, scene, ocr_text, confidence, analyzed_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(item_id) DO UPDATE SET
                        provider_id = excluded.provider_id,
                        model_version = excluded.model_version,
                        caption = excluded.caption,
                        tags_json = excluded.tags_json,
                        objects_json = excluded.objects_json,
                        scene = excluded.scene,
                        ocr_text = excluded.ocr_text,
                        confidence = excluded.confidence,
                        analyzed_at = excluded.analyzed_at
                """,
                arguments: args
            )

            let filename: String = try Row.fetchOne(
                db,
                sql: "SELECT filename FROM media_items WHERE id = ?",
                arguments: [itemID.rawValue]
            )?["filename"] ?? ""
            let folderPath: String = try Row.fetchOne(
                db,
                sql: "SELECT relative_path FROM media_items WHERE id = ?",
                arguments: [itemID.rawValue]
            )?["relative_path"] ?? ""

            try db.execute(sql: "DELETE FROM media_fts WHERE rowid = ?", arguments: [itemID.rawValue])
            try db.execute(
                sql: """
                    INSERT INTO media_fts (rowid, filename, folder_path, caption, tags, ocr)
                    VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    itemID.rawValue,
                    filename,
                    folderPath,
                    caption ?? "",
                    Self.tagsFTSText(tagsJSON: tagsJSON, objectsJSON: objectsJSON, scene: scene),
                    ocrText ?? ""
                ] as StatementArguments
            )

            try db.execute(
                sql: "UPDATE media_items SET ai_state = 'ready' WHERE id = ?",
                arguments: [itemID.rawValue]
            )
        }
    }

    private static func tagsFTSText(tagsJSON: String?, objectsJSON: String?, scene: String?) -> String {
        var parts: [String] = []
        if let tagsJSON, let data = tagsJSON.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            parts.append(contentsOf: arr)
        }
        if let objectsJSON, let data = objectsJSON.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            parts.append(contentsOf: arr)
        }
        if let scene { parts.append(scene) }
        return parts.joined(separator: " ")
    }

    public func writeAIEmbedding(
        itemID: MediaItemID,
        providerID: Int64?,
        modelVersion: String,
        dim: Int,
        vectorPath: String
    ) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO ai_embeddings (item_id, provider_id, model_version, dim, vector_path)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(item_id) DO UPDATE SET
                        provider_id = excluded.provider_id,
                        model_version = excluded.model_version,
                        dim = excluded.dim,
                        vector_path = excluded.vector_path
                """,
                arguments: [
                    itemID.rawValue,
                    providerID,
                    modelVersion,
                    dim,
                    vectorPath
                ] as StatementArguments
            )
        }
    }

    public func clearAIForRoot(_ rootID: WatchedRootID) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    DELETE FROM ai_enrichment WHERE item_id IN (
                        SELECT id FROM media_items WHERE root_id = ?
                    )
                """,
                arguments: [rootID.rawValue]
            )
            try db.execute(
                sql: """
                    DELETE FROM ai_embeddings WHERE item_id IN (
                        SELECT id FROM media_items WHERE root_id = ?
                    )
                """,
                arguments: [rootID.rawValue]
            )
            try db.execute(
                sql: """
                    UPDATE media_items SET ai_state = 'none' WHERE root_id = ?
                """,
                arguments: [rootID.rawValue]
            )
            try db.execute(sql: """
                DELETE FROM media_fts WHERE rowid IN (
                    SELECT id FROM media_items WHERE root_id = ?
                )
            """, arguments: [rootID.rawValue])
        }
    }

    public func clearAllAI() async throws {
        try await db.write { db in
            try db.execute(sql: "DELETE FROM ai_enrichment")
            try db.execute(sql: "DELETE FROM ai_embeddings")
            try db.execute(sql: "UPDATE media_items SET ai_state = 'none'")
            try db.execute(sql: "DELETE FROM jobs WHERE kind = 'ai'")
        }
    }

    public func setFolderAIEnabled(_ folderID: FolderID, enabled: Bool) async throws {
        try await db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                arguments: ["ai.folder.\(folderID.rawValue)", enabled ? "1" : "0"]
            )
        }
    }

    public func isFolderAIEnabled(_ folderID: FolderID) async throws -> Bool {
        try await db.read { db in
            let value = try String.fetchOne(
                db,
                sql: "SELECT value FROM settings WHERE key = ?",
                arguments: ["ai.folder.\(folderID.rawValue)"]
            )
            return value == "1"
        }
    }

    public func resetStuckJobs() async throws {
        try await db.write { db in
            try db.execute(sql: "UPDATE jobs SET state = 'queued' WHERE kind = 'ai' AND state = 'running'")
        }
    }

    public func cleanOrphanJobs() async throws {
        try await db.write { db in
            try db.execute(sql: """
                DELETE FROM jobs WHERE kind = 'ai'
                AND target_id NOT IN (SELECT id FROM media_items)
            """)
        }
    }

    public func rebuildCatalog() async throws {
        try await db.write { db in
            try db.execute(sql: "DELETE FROM media_fts")
            try db.execute(sql: "DELETE FROM thumbnails")
            try db.execute(sql: "DELETE FROM metadata")
            try db.execute(sql: "DELETE FROM media_items")
            try db.execute(sql: "DELETE FROM folders")
            try db.execute(sql: "DELETE FROM jobs")
        }
    }
}
