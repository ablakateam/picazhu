# PICAZHU for macOS — Project Status

_Last updated: 2026-04-17_

## TL;DR

Phase 1 (browser) stable. **Phase 2 (AI) fully functional** — tested end-to-end with both local Ollama (`qwen3-vl:8b`) and Ollama Cloud (`qwen3-vl:235b-instruct`). In-app AI Settings with provider switching, live debug console, neural-scan visual effects on thumbnails during analysis, sub-stage progress bar, model auto-warmup on launch and auto-unload on quit. Apple Developer account applied for; `DISTRIBUTION.md` has the full signing/notarization playbook.

## Architecture

```
PICAZHU/
├─ PICAZHU.xcodeproj              # Xcode 26, objectVersion 77
├─ App/                           # SwiftUI app target
│  ├─ PicazhuMacApp.swift         # scenes, commands, menu bar
│  ├─ AppEnvironment.swift        # DI container (Phase 1 + AI stack)
│  ├─ LibraryViewModel.swift      # @Observable, all UI state
│  ├─ RootView.swift              # 3-column layout, breadcrumbs, sidebar
│  ├─ AIAdapters.swift            # ThumbnailSourceAdapter, OCRAdapter, EmbeddingStoreAdapter
│  ├─ OllamaStatus.swift          # health pill model + view
│  ├─ PicazhuMacApp.entitlements
│  └─ Info.plist
├─ PicazhuKit/                    # local SPM package, 10 library products
│  ├─ Package.swift               # sole external dep: GRDB.swift 7.x
│  └─ Sources/
│     ├─ PicazhuCore              # domain types, IDs, MediaKind, errors, OSLog
│     ├─ PicazhuData              # GRDB, migrations (v1+v2+v3), CatalogWriter, repos
│     ├─ PicazhuMedia             # Image I/O, AVFoundation, ThumbnailService + cache
│     ├─ PicazhuIndexing          # BookmarkStore, SecurityScope, streaming scanner, coordinator, FSEvents
│     ├─ PicazhuPreview           # Quick Look bridge, MetadataFormatter
│     ├─ PicazhuSearch            # SearchQuery, SearchEngine, HybridSearchEngine, EmbeddingStore
│     ├─ PicazhuAI                # AIProvider protocol, OllamaClient, OllamaVisionProvider, AIEnrichmentCoordinator
│     ├─ PicazhuVision            # OCRService (Apple Vision VNRecognizeTextRequest)
│     ├─ PicazhuDiagnostics       # HealthChecks + DiagnosticsSnapshot
│     └─ PicazhuUI                # DesignTokens, MediaGrid, InspectorView, AIProgressBar, AIInspectorSection, DiagnosticsView, EmptyStates
└─ build/
   ├─ PICAZHU.app                 # latest Release build (arm64, ad-hoc)
   └─ DerivedData/
```

## Schema (3 migrations)

| Migration | Purpose |
|---|---|
| `v1_initial_schema` | 14 tables + FTS5 (`media_fts`). AI tables created upfront. |
| `v2_contentless_delete_fts` | Drops + recreates `media_fts` with `contentless_delete=1`. Reseeds from existing `media_items` + `ai_enrichment`. Fixes the critical bug where `DELETE FROM media_fts WHERE rowid=?` threw on contentless FTS5. |
| `v3_reset_failed_ai_jobs` | Clears the ~273 failed AI jobs and resets `ai_state` to `'none'` so users can cleanly re-trigger Analyze with AI. |

## Phase 1 — Browser (stable, complete)

- Folder management via `NSOpenPanel` + security-scoped bookmarks
- Streaming two-stage indexing (Stage A: fast file scan, Stage B: thumbnails + metadata)
- Recursive `ensureFolderChain` for correct parent hierarchy
- Self-healing `upsertFolder` corrects `parent_id`/`depth` on re-scan
- `QLThumbnailGenerator` + `AVAssetImageGenerator` fallback, SHA-256-keyed sharded disk cache
- Image I/O (EXIF/GPS) + AVFoundation (duration/codec) metadata
- FSEvents folder watching with 500 ms debounce
- Three-column `NavigationSplitView`: sidebar (selection highlight, item counts, access badges), content (breadcrumbs, adaptive grid, search), inspector
- Quick Look (`⌘Space`), Open (`⌘↩`), Reveal in Finder (`⌘⇧R`), Copy Path (`⌘⌥C`)
- FTS5 search scoped to current folder
- Diagnostics window (`⌘⇧D`): roots, counts, queues, cache/DB sizes, integrity check, purge, rebuild
- Clear Library (`File → Clear Library…`) + per-root remove with confirmation

## Phase 2 — AI (wired, critical bug fixed, ready to test)

### Stack
- **VLM:** Qwen2.5-VL 7B (`qwen2.5vl:7b`) via Ollama at `localhost:11434`
- **Embeddings:** nomic-embed-text (`nomic-embed-text`) via Ollama
- **OCR:** Apple Vision `VNRecognizeTextRequest(.accurate, revision3)` — local, free, fast
- **Privacy:** only 512 px thumbnails are sent; originals never leave the app

### Pipeline per image
1. Apple Vision OCR extracts any text → `ai_enrichment.ocr_text`
2. Qwen2.5-VL generates structured JSON: `{caption, tags[], objects[], scene, confidence}` → `ai_enrichment.*`
3. nomic-embed-text embeds the caption → on-disk `Float32[]` vector → `ai_embeddings.vector_path`
4. All text mirrored into `media_fts(caption, tags, ocr)` for FTS5 search
5. `ai_state` flipped to `'ready'`

### UI entry points for Analyze
1. **Toolbar** — `Analyze` (sparkles button). With selection: analyzes just selected items. Without: analyzes entire current folder.
2. **File menu** — `File → Analyze Current Folder with AI` (`⌘⇧I`)
3. **Sidebar hover** — sparkles icon appears on hover over any folder row
4. **Right-click folder** — context menu → `Analyze with AI`
5. **Inspector** — `Analyze Now` button on any un-analyzed item

### Progress UI
- **Bottom bar:** persistent when AI worker is active. Shows stage icon (OCR/VLM/Embed), filename, `N/M`, ETA (EMA-smoothed), pause/resume, cancel.
- **Toolbar chip:** compact percentage + count mirror.

### Search
`HybridSearchEngine` fuses FTS5 BM25 (60%) + cosine similarity over caption embeddings (40%). Falls back to pure FTS5 when no embeddings exist.

### Ollama health pill
Top-right toolbar. Color-coded:
- Gray = checking
- Red = unreachable
- Orange = model missing
- Yellow = ready (cold, model not in RAM)
- Green = ready (warm, model loaded in RAM with VRAM size)

Refreshes every 5 s; click to force refresh.

### Diagnostics AI section
Enriched/pending/failed counts, embeddings stored, active provider name, **Clear all AI data** button.

## Verified end-to-end

| What | How verified |
|---|---|
| Ollama VLM structured output | `curl` test against `qwen2.5vl:7b` with JSON schema — returns valid `{caption, tags, objects, scene, confidence}` in 13 s |
| nomic-embed-text | `curl` test returns 768-dim float vector |
| FTS5 contentless_delete=1 | SQLite CLI: `DELETE` succeeds after `INSERT` on the new schema |
| Regression test | `testWriteAIEnrichmentReWriteSucceeds` — inserts FTS row, then re-writes AI enrichment (was the crash path), verifies FTS update + count = 1 |
| All package tests | 6/6 passing (3 data, 1 scanner, 1 search, 1 cache) |
| App build | `xcodebuild -configuration Release` → BUILD SUCCEEDED |

## Bugs found and fixed (audit log)

1. **FTS5 contentless DELETE crash** (root cause of "stuck at 0%"): `media_fts` was created with `content=''` but WITHOUT `contentless_delete=1`. SQLite refuses `DELETE FROM contentless fts5 table`. Every AI persist step crashed silently. Fixed with v2 migration + regression test.
2. **"folder disabled" rejection**: coordinator re-checked `isFolderAIEnabled` before each job but the single-item inspector path never enabled the folder. Removed the re-check (user action = opt-in) and made `reanalyzeSelection` explicitly enable the folder.
3. **Context menu not showing on folder rows**: `.contextMenu` on a `Button` inside a `DisclosureGroup` label was swallowed by SwiftUI hit-testing. Refactored to `HStack + .onTapGesture + .contextMenu` and added hover sparkles button.
4. **Toolbar Analyze enqueued entire folder instead of selection**: now prioritizes selection if non-empty.
5. **OCR wasted on video files**: `CGImageSourceCreateWithURL` fails on `.mp4`/`.mov`, was throwing then swallowed. Now skipped for `kind == .video`.
6. **OSLog privacy masking**: all AI log messages were `<private>`. Changed to `privacy: .public` for debugging.
7. **273 stale failed jobs**: v3 migration clears the backlog.

## Build, test, run

```bash
cd /Users/danglad/Desktop/PICAZHU

# Build
xcodebuild -project PICAZHU.xcodeproj -scheme PICAZHU \
  -configuration Release -derivedDataPath build/DerivedData build
cp -R build/DerivedData/Build/Products/Release/PICAZHU.app build/PICAZHU.app
open build/PICAZHU.app

# Tests (6/6)
cd PicazhuKit && swift test

# AI logs (Terminal)
log stream --predicate 'subsystem == "com.picazhu.mac" AND category == "ai"' --level info

# All logs
log stream --subsystem com.picazhu.mac --level debug
```

## Ollama prerequisite

```bash
ollama pull qwen2.5vl:7b        # ~6 GB, VLM for captioning
ollama pull nomic-embed-text     # ~274 MB, text embeddings
curl http://localhost:11434/api/tags | jq .   # verify
```

## Known issues / deferred

### Phase 1.5 (browser polish)
1. `LazyVGrid` not virtualised — fine to ~10k items per folder
2. Thumbnail enrichment isn't priority-aware for visible folder
3. Sidebar re-renders on every scan tick via refresh token
4. No sort/filter chip UI (engine supports it, UI doesn't surface it)
5. Saved searches / pinned folders UI not wired
6. Scan cancellation not implemented
7. App icon is the generic SwiftUI placeholder

### Phase 2.1 (remaining)
1. **Video keyframe handling** — videos get one poster-frame caption; 5-frame sampling + merge not built yet
2. ~~AI Settings window~~ — DONE: in-app sheet with Local/Cloud toggle, API key, model dropdowns, Test Connection
3. **Automated AI-path tests** — test targets exist but only the regression test has real content
4. **OpenAI provider adapter** — protocol is ready, no implementation
5. **Concurrent enrichment** — worker processes 1 job at a time; 2-way parallelism planned
6. **Embedding ANN index** — in-memory cosine scan works to ~50k items; proper index deferred
7. **Per-folder AI disable toggle in UI** — settings table supports it, no checkbox in sidebar

### Phase 1.5 (browser polish, updated)
1. `LazyVGrid` not virtualised — fine to ~10k items per folder
2. No sort/filter chip UI (engine supports it, UI doesn't surface it)
3. Saved searches / pinned folders UI not wired
4. ~~App icon~~ — DONE: custom icon from `pikazhu_logo.png`

### Distribution
- Apple Developer account applied for (pending approval)
- Full signing/notarization/DMG guide in `DISTRIBUTION.md`

## Memory / references for future sessions

- Project memory: `~/.claude/projects/-Users-danglad-Desktop-PICAZHU/memory/project_picazhu.md`
- Paths reference: `~/.claude/projects/-Users-danglad-Desktop-PICAZHU/memory/reference_picazhu_paths.md`
- Phase 2 plan: `~/.claude/plans/fancy-knitting-turing.md`
- Catalog DB (sandboxed): `~/Library/Containers/com.picazhu.mac/Data/Library/Application Support/PICAZHU/catalog.sqlite`
- Thumbnail cache (sandboxed): `~/Library/Containers/com.picazhu.mac/Data/Library/Caches/PICAZHU/thumbs/`
- Embedding vectors (sandboxed): `~/Library/Containers/com.picazhu.mac/Data/Library/Application Support/PICAZHU/embeddings/`
