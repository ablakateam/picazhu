import Foundation
import GRDB

public enum Migrations {
    public static func migrator() -> DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1_initial_schema") { db in
            try db.execute(sql: """
                CREATE TABLE watched_roots (
                    id INTEGER PRIMARY KEY,
                    display_name TEXT NOT NULL,
                    bookmark BLOB NOT NULL,
                    last_scan_at REAL,
                    access_state TEXT NOT NULL,
                    created_at REAL NOT NULL
                );
            """)

            try db.execute(sql: """
                CREATE TABLE folders (
                    id INTEGER PRIMARY KEY,
                    root_id INTEGER NOT NULL REFERENCES watched_roots(id) ON DELETE CASCADE,
                    parent_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,
                    relative_path TEXT NOT NULL,
                    name TEXT NOT NULL,
                    depth INTEGER NOT NULL,
                    item_count INTEGER NOT NULL DEFAULT 0,
                    child_count INTEGER NOT NULL DEFAULT 0,
                    UNIQUE(root_id, relative_path)
                );
            """)
            try db.execute(sql: "CREATE INDEX idx_folders_parent ON folders(parent_id);")

            try db.execute(sql: """
                CREATE TABLE media_items (
                    id INTEGER PRIMARY KEY,
                    folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
                    root_id INTEGER NOT NULL REFERENCES watched_roots(id) ON DELETE CASCADE,
                    filename TEXT NOT NULL,
                    relative_path TEXT NOT NULL,
                    extension TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    size INTEGER NOT NULL,
                    created_at REAL,
                    modified_at REAL NOT NULL,
                    width INTEGER,
                    height INTEGER,
                    duration REAL,
                    orientation INTEGER,
                    content_hash TEXT,
                    thumb_state TEXT NOT NULL,
                    meta_state TEXT NOT NULL,
                    ai_state TEXT NOT NULL DEFAULT 'none',
                    indexed_at REAL NOT NULL,
                    UNIQUE(root_id, relative_path)
                );
            """)
            try db.execute(sql: "CREATE INDEX idx_media_folder ON media_items(folder_id);")
            try db.execute(sql: "CREATE INDEX idx_media_modified ON media_items(modified_at);")
            try db.execute(sql: "CREATE INDEX idx_media_kind_size ON media_items(kind, size);")

            try db.execute(sql: """
                CREATE TABLE metadata (
                    item_id INTEGER PRIMARY KEY REFERENCES media_items(id) ON DELETE CASCADE,
                    exif_json TEXT,
                    camera_make TEXT,
                    camera_model TEXT,
                    lens TEXT,
                    iso INTEGER,
                    f_number REAL,
                    exposure_time REAL,
                    focal_length REAL,
                    capture_time REAL,
                    gps_lat REAL,
                    gps_lon REAL,
                    codec TEXT
                );
            """)

            try db.execute(sql: """
                CREATE TABLE thumbnails (
                    item_id INTEGER PRIMARY KEY REFERENCES media_items(id) ON DELETE CASCADE,
                    cache_key TEXT NOT NULL,
                    pixel_size INTEGER NOT NULL,
                    generated_at REAL NOT NULL
                );
            """)

            try db.execute(sql: """
                CREATE TABLE jobs (
                    id INTEGER PRIMARY KEY,
                    kind TEXT NOT NULL,
                    target_id INTEGER,
                    state TEXT NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0,
                    error TEXT,
                    enqueued_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );
            """)
            try db.execute(sql: "CREATE INDEX idx_jobs_state_kind ON jobs(state, kind);")

            try db.execute(sql: """
                CREATE TABLE saved_searches (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    query_json TEXT NOT NULL,
                    pinned INTEGER NOT NULL DEFAULT 0,
                    created_at REAL NOT NULL
                );
            """)

            try db.execute(sql: """
                CREATE TABLE pinned_folders (
                    folder_id INTEGER PRIMARY KEY REFERENCES folders(id) ON DELETE CASCADE,
                    pinned_at REAL NOT NULL
                );
            """)

            try db.execute(sql: """
                CREATE TABLE recent_folders (
                    folder_id INTEGER PRIMARY KEY REFERENCES folders(id) ON DELETE CASCADE,
                    visited_at REAL NOT NULL
                );
            """)

            try db.execute(sql: """
                CREATE TABLE settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
            """)

            try db.execute(sql: """
                CREATE TABLE ai_providers (
                    id INTEGER PRIMARY KEY,
                    kind TEXT NOT NULL,
                    name TEXT NOT NULL,
                    config_json TEXT NOT NULL,
                    enabled INTEGER NOT NULL DEFAULT 0,
                    created_at REAL NOT NULL
                );
            """)

            try db.execute(sql: """
                CREATE TABLE ai_enrichment (
                    item_id INTEGER PRIMARY KEY REFERENCES media_items(id) ON DELETE CASCADE,
                    provider_id INTEGER REFERENCES ai_providers(id) ON DELETE SET NULL,
                    model_version TEXT,
                    caption TEXT,
                    tags_json TEXT,
                    objects_json TEXT,
                    scene TEXT,
                    ocr_text TEXT,
                    confidence REAL,
                    analyzed_at REAL NOT NULL
                );
            """)

            try db.execute(sql: """
                CREATE TABLE ai_embeddings (
                    item_id INTEGER PRIMARY KEY REFERENCES media_items(id) ON DELETE CASCADE,
                    provider_id INTEGER REFERENCES ai_providers(id) ON DELETE SET NULL,
                    model_version TEXT NOT NULL,
                    dim INTEGER NOT NULL,
                    vector_path TEXT NOT NULL
                );
            """)

            try db.execute(sql: """
                CREATE VIRTUAL TABLE media_fts USING fts5(
                    filename, folder_path, caption, tags, ocr,
                    content='',
                    tokenize='unicode61 remove_diacritics 2'
                );
            """)
        }

        m.registerMigration("v2_contentless_delete_fts") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS media_fts;")
            try db.execute(sql: """
                CREATE VIRTUAL TABLE media_fts USING fts5(
                    filename, folder_path, caption, tags, ocr,
                    content='',
                    contentless_delete=1,
                    tokenize='unicode61 remove_diacritics 2'
                );
            """)

            try db.execute(sql: """
                INSERT INTO media_fts(rowid, filename, folder_path, caption, tags, ocr)
                SELECT
                    m.id,
                    COALESCE(m.filename, ''),
                    COALESCE((SELECT relative_path FROM folders WHERE id = m.folder_id), ''),
                    COALESCE(e.caption, ''),
                    COALESCE(e.tags_json, '') || ' ' || COALESCE(e.objects_json, '') || ' ' || COALESCE(e.scene, ''),
                    COALESCE(e.ocr_text, '')
                FROM media_items m
                LEFT JOIN ai_enrichment e ON e.item_id = m.id;
            """)
        }

        m.registerMigration("v3_reset_failed_ai_jobs") { db in
            // The previous coordinator left ~hundreds of AI jobs in 'failed' state
            // because of the contentless FTS5 DELETE bug fixed in v2. Clear them so
            // users can re-trigger Analyze with AI cleanly without the failed
            // backlog appearing in diagnostics and confusing the worker.
            try db.execute(sql: "DELETE FROM jobs WHERE kind = 'ai' AND state IN ('failed', 'queued');")
            try db.execute(sql: "UPDATE media_items SET ai_state = 'none' WHERE ai_state IN ('pending', 'failed');")
        }

        return m
    }
}
