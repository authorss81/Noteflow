# Noteflow — Detailed Roadmap

> Last updated: 2026-08-02
> Hardware constraint: AMD Athlon 200GE (2C/4T, ~2.7 GB free RAM)
> Build strategy: cloud builds via GitHub Actions (no local Android SDK)
> All dependencies must be FOSS or free for commercial use.

---

## Status summary

| Phase | Status |
|---|---|
| P0 — Make it actually work | ✅ done (7/7) |
| P1 — Usable day-to-day | ✅ done (10/10) |
| P2 — Feels like a real annotation app | 🔄 in progress |
| P3 — Data safety & multi-device | 📋 planned |
| P4 — World-class features | 📋 planned |

---

## Bug fixes applied 2026-08-02

| # | Bug | Fix |
|---|---|---|
| B1 | Trash "Empty trash" did not refresh the UI | Added `await _reloadTree()` to `AppState.emptyTrash()` |
| B2 | PDF import: back arrow (←) and redo arrow (⟳) superimposed in editor AppBar | Added `automaticallyImplyLeading: false` + explicit back button (`Icons.arrow_back`) |
| B3 | Web build fails with `driftDatabase` error | Upgraded `drift_flutter` 0.2.8 → 0.3.1, added `DriftWebOptions`, updated `sqlite3.wasm` + `drift_worker.js` to drift-2.34.3 release |

---

## Phase P2 — "Feels like a real annotation app"

### P2-1: Multipage PDF import (currently only page 1 renders)

**Problem:** `pdfrx` renders only the first page. Users importing multi-page PDFs see only page 1.

**Approach:**
- Iterate `PdfDocument.pages` (all pages, not just `.first`)
- For each page, render to an image via `page.render(width, height)` → `ui.decodeImageFromPixels`
- Create a separate `NotePage` per PDF page, each with the rendered image as background
- Store the original PDF bytes in `sourceFilePath` for re-rendering at higher quality if needed

**Complexity:** Medium
**CPU impact:** Low — PDF rendering is single-threaded and fast on Athlon 200GE for typical documents (1–20 pages). For 50+ page PDFs, process in background isolate.
**GitHub Actions:** Headless — no rendering needed in CI.
**Dependencies:** `pdfrx` (already imported)

---

### P2-2: Import as vector (PDF) vs pixel (images)

**Problem:** All imports are rasterized. Vector PDF data is lost.

**Approach:**
- PDF: keep raw bytes + re-render on demand via `pdfrx` (already vector-aware internally)
- Images: store as filesystem files with `sourceFilePath`, use `image` package for metadata/processing
- Add a `sourceFileType` column that distinguishes `pdf-vector` from `image-raster` from `text-plain`

**Complexity:** Easy (PDF) / Easy (image)
**CPU impact:** Negligible
**Dependencies:** `image` (Dart package, pure Dart)

---

### P2-3: Markdown file support (.md import/preview)

**Approach:**
- Detect `.md` extension at import
- Parse with `markdown` package (Dart, pure Dart, no native deps)
- Store raw `.md` text + rendered preview in database
- Render with `flutter_markdown_plus` in a read-only preview mode

**Complexity:** Easy
**CPU impact:** Negligible
**Dependencies:** `markdown`, `flutter_markdown_plus`

---

### P2-4: Custom brushes, stroke width, brightness/contrast

**Approach:**
- Stroke width: `Slider` in editor toolbar, passed to canvas `Paint`
- Brightness/contrast for PDF backgrounds: `ColorFilter.matrix()` on the background image
- Color picker with recent colors: `flex_color_picker` (FOSS, MIT license)
- Shape fill toggle (filled vs outline): `PaintingStyle.fill` / `PaintingStyle.stroke`

**Complexity:** Medium (all combined)
**CPU impact:** Negligible (sliders are UI-only; color filtering is GPU-accelerated)
**Dependencies:** `flex_color_picker`

---

### P2-5: Text annotation formatting (bold, italic, underline)

**Approach:**
- When text tool is active, show formatting toggles in toolbar
- Apply `TextStyle` (bold, italic, underline) to `StrokeTool.text` strokes
- Store style info in the Stroke model's `textStyle` field

**Complexity:** Easy
**CPU impact:** Negligible
**Dependencies:** None (uses built-in `TextStyle`)

---

### P2-6: Tags and categories (beyond notebooks/sections/pages)

**Approach:**
- Add `tags` table + `page_tags` junction table to drift schema
- `Tag` model: `id`, `name`, `color`, `createdAt`
- Filter pages by tag in home screen
- Tag chips in page detail

**Complexity:** Easy
**CPU impact:** Negligible (indexed SQL joins)
**Dependencies:** None (drift handles junction tables natively)

---

### P2-7: Fuzzy search across all notes

**Approach:**
- Add SQLite FTS5 virtual table via drift: `CREATE VIRTUAL TABLE pages_fts USING fts5(content, title, tags)`
- On every save, update the FTS index
- Debounced search with ranking

**Complexity:** Medium
**CPU impact:** Low — FTS5 is highly optimized; Athlon 200GE handles hundreds of pages instantly
**GitHub Actions:** Testable in CI (headless SQL)
**Dependencies:** `drift` (already supports raw SQL for FTS5)

---

### P2-8: Batch operations (select multiple pages, move/delete)

**Approach:**
- Long-press or checkbox selection mode on page list
- Multi-select with `Set<String>` of selected IDs
- Batch move, batch delete, batch tag in single transaction

**Complexity:** Easy
**CPU impact:** Negligible
**Dependencies:** None

---

### P2-9: Export page as PNG/PDF + share

**Approach:**
- PNG: `RepaintBoundary.toImage()` → `ui.Image.toByteData(format: png)` → save/share
- PDF: `pdf` package to generate a PDF from the annotation canvas
- ZIP: `archive` package to bundle all page exports

**Complexity:** Medium
**CPU impact:** Low (PNG rendering is GPU-accelerated)
**Dependencies:** `pdf`, `archive`, `share_plus`

---

### P2-10: Page templates (blank, lined, grid, dot grid)

**Approach:**
- `Template` model: `id`, `name`, `type` (blank/lined/grid/dot), `config` (JSON: line spacing, color, etc.)
- Render template as `CustomPainter` background layer on canvas
- User can select template when creating a new page

**Complexity:** Easy
**CPU impact:** Negligible (CustomPainter is cheap)
**Dependencies:** None

---

### P2-11: Word count / page statistics

**Approach:**
- For text pages: split by whitespace, count tokens
- For annotated pages: count strokes + text annotations
- Display in page detail header or a stats panel

**Complexity:** Easy
**CPU impact:** Negligible
**Dependencies:** None

---

### P2-12: Version control features (checkpoints, diff, named versions)

**Approach:**
- Named checkpoints: user can name a version snapshot (already partially done with `label` field)
- Diff between versions: compare serialized stroke JSON arrays (position, color, width, text)
- For text annotations: compare `text` field + position
- Visual diff: highlight changed regions

**Complexity:** Hard (diff algorithm) / Easy (checkpoint naming)
**CPU impact:** Low (JSON comparison is fast for typical stroke counts)
**Dependencies:** `diff_match_patch` (Dart port) for text diffing

---

### P2-13: Lossless compression of version history

**Approach:**
- Delta encoding: store only diffs between versions instead of full snapshots
- SQLite `COMPRESS`/`UNCOMPRESS` or Dart `zlib`/`gzip` for BLOB compression
- Prune old versions: keep every Nth full snapshot + deltas in between
- Run `VACUUM` periodically to reclaim space

**Complexity:** Medium
**CPU impact:** Low (zlib compression is fast on Athlon 200GE)
**Dependencies:** `archive` (Dart, pure Dart)

---

### P2-14: Database optimization (VACUUM, compaction, pruning)

**Approach:**
- Add `PRAGMA optimize` on app startup
- Configurable version retention policy (e.g., keep last 50 versions per page)
- Background `VACUUM` after large deletions
- Index on frequently queried columns

**Complexity:** Medium
**CPU impact:** Low (VACUUM is I/O-bound, not CPU-bound)
**Dependencies:** None (drift supports raw SQL)

---

### P2-15: Dark mode auto-detection (system theme)

**Approach:**
- Add `ThemeMode.system` option alongside `light`, `dark`, `sepia`, `AMOLED`
- Listen to `WidgetsBinding.instance.addObserver` for `didChangePlatformBrightness`
- Persist preference in `SettingsService`

**Complexity:** Easy
**CPU impact:** Negligible
**Dependencies:** None

---

## Phase P3 — "Data safety & multi-device"

### P3-1: E2E encryption for notes

**Integration Type:** Core Feature
**Approach:**
- Use existing `cryptography` package (already imported)
- **Key derivation:** Argon2id from user password (built into `cryptography`)
- **Encryption:** AES-256-GCM for note content (authenticated encryption)
- **Key storage:** `flutter_secure_storage` (already imported) — Android Keystore / iOS Keychain / DPAPI on Windows
- **Web:** Web Crypto API (built into `cryptography` package, works on HTTPS)
- **Flow:** User sets a master password → derive KEK → encrypt DEK → store DEK encrypted in secure storage → encrypt each note's strokes JSON with DEK

**Complexity:** Medium
**CPU impact:** Low (Argon2id is configurable; AES-GCM is hardware-accelerated on modern CPUs)
**Dependencies:** `cryptography` (already imported), `flutter_secure_storage` (already imported)

---

### P3-2: Biometric authentication (fingerprint / face)

**Integration Type:** Core Feature
**Approach:**
- `flutter_biometric_auth_plus` — FOSS, works on all 6 platforms including web (WebAuthn)
- PIN fallback using `flutter_auth_screen` (pure UI, no business logic)
- Auto-lock on app background (`WidgetsBindingObserver` + `AppLifecycleListener`)
- Store PIN hash with Argon2id in `flutter_secure_storage`

**Complexity:** Easy–Medium
**CPU impact:** Negligible
**Dependencies:** `flutter_biometric_auth_plus`, `flutter_auth_screen`

---

### P3-3: Secure backup/export with encryption

**Integration Type:** Core Feature
**Approach:**
- Export: `.noteflow` ZIP containing (manifest.json + 5 tables JSON + files/)
- Encrypt ZIP with AES-256-GCM using a user-chosen password
- Derive key via Argon2id from password
- Import: decrypt → verify → extract → load into database

**Complexity:** Medium
**CPU impact:** Low (zlib + AES-GCM is fast on Athlon 200GE)
**Dependencies:** `archive` (already used for ZIP), `cryptography` (already imported)

---

### P3-4: LocalSend integration (peer-to-peer sharing)

**Integration Type:** Core Feature (Native REST Client)
**Approach:**
- LocalSend uses a documented REST API over HTTPS on port 53317
- Implement a client in Dart using `http` package
- Key endpoints: discovery (UDP multicast), upload, download
- Share notes as JSON or exported files to other devices on the same network

**Complexity:** Medium
**CPU impact:** Negligible
**Dependencies:** `http` (already a transitive dependency)

---

### P3-5: PDF24-style PDF tools (merge, split, compress)

**Integration Type:** Core Feature (Native Library)
**Approach:**
- Implement natively in Flutter — do NOT depend on PDF24's web tools
- `pdf_utils` or `pdf_manipulator` package for merge/split/compress
- Add a "PDF tools" option in the import/export menu

**Complexity:** Medium
**CPU impact:** Low–Medium (PDF manipulation is CPU-bound but manageable)
**Dependencies:** `pdf_utils` or `pdf_manipulator`

---

### P3-6: OCR with Tesseract (searchable notes from images/PDFs)

**Integration Type:** Optional Plugin
**Approach:**
- `tesseract_ocr` package for on-device OCR
- Bundle `eng.traineddata` in app assets
- On import of images/PDFs, run OCR in background isolate
- Store extracted text as a searchable `textContent` field on pages
- Full-text search uses the FTS5 index (P2-7)

**Complexity:** Medium
**CPU impact:** Medium — OCR is CPU-intensive but runs in background isolate. Athlon 200GE can handle it for typical note-sized images.
**GitHub Actions:** Headless — no OCR testing in CI (requires image assets)
**Dependencies:** `tesseract_ocr`

---

### P3-7: Markdown + LaTeX rendering for notes

**Integration Type:** Core Feature
**Approach:**
- `flutter_markdown_plus` for Markdown rendering
- `ratex_flutter` for LaTeX (native Dart FFI, no WebView, best performance)
- Users can write notes in Markdown/LaTeX and preview rendered output

**Complexity:** Easy
**CPU impact:** Negligible (rendering is GPU-accelerated)
**Dependencies:** `flutter_markdown_plus`, `ratex_flutter`

---

### P3-8: LibreOffice document conversion (DOCX → PDF)

**Integration Type:** Optional Plugin
**Approach:**
- `libre_office_kit_converter_plugin` for offline DOCX/XLSX/PPTX → PDF conversion
- Converts documents to PDF, then user can annotate them in Noteflow
- **Note:** LibreOfficeKit adds ~600 MB to app size — only bundle on Android/iOS, not web/desktop

**Complexity:** Medium–Hard (large native dependency)
**CPU impact:** Medium (document conversion is CPU-intensive)
**Dependencies:** `libre_office_kit_converter_plugin`

---

### P3-9: Bitwarden vault integration (password-protected notes)

**Integration Type:** External Integration
**Approach:**
- Use Bitwarden's Vault Management API (`bw serve` CLI) for programmatic access
- Store encryption keys for protected notes in Bitwarden
- `url_launcher` to open Bitwarden for copy/paste workflows
- **Note:** Full API integration requires `bw serve` running locally — optional, advanced feature

**Complexity:** Medium–Hard
**CPU impact:** Negligible
**Dependencies:** `url_launcher` (already a transitive dependency)

---

### P3-10: 7-Zip / archive compression for exports

**Integration Type:** Core Feature
**Approach:**
- `archive` package (pure Dart) for ZIP/gzip/tar creation
- Use for encrypted backup exports and batch file sharing
- For 7z format specifically: `flutter_7zip` on desktop platforms only

**Complexity:** Easy
**CPU impact:** Low (zlib is fast)
**Dependencies:** `archive` (already used)

---

### P3-11: HandBrake-style video compression (for video notes)

**Integration Type:** Declined (Replaced by Native Light Compressor)
**Approach:**
- `video_compress` or `v_video_compressor` for in-app video compression
- **Not** HandBrake integration (no CLI/API available)
- Useful if users attach video recordings to notes

**Complexity:** Easy
**CPU impact:** Medium (video encoding is CPU-intensive, runs in isolate)
**Dependencies:** `video_compress`

---

## Phase P4 — "World-class"

### P4-1: Diagramming & mind maps

**Approach:**
- `flutter_flow_chart` for flowcharts
- Mermaid.js via WebView for sequence/class/state diagrams
- `drawflow` JavaScript library via WebView for advanced diagramming

**Complexity:** Medium–Hard
**CPU impact:** Low (rendering is GPU-accelerated)
**Dependencies:** `flutter_flow_chart`, WebView

---

### P4-2: Home screen widgets (Android shortcuts, iOS widgets)

**Approach:**
- `home_widget` for cross-platform home screen widgets
- Show recent page title, last edited time, quick-create shortcut
- Android: `ShortcutManager` for pinned shortcuts
- iOS: `WidgetKit` via `home_widget`

**Complexity:** Hard (especially iOS widgets, requires native Swift code)
**CPU impact:** N/A (platform feature)
**Dependencies:** `home_widget`, `quick_actions`

---

### P4-3: Passkey-based authentication (WebAuthn/FIDO2)

**Approach:**
- `passkeys` package for cross-platform passkey support
- PRF extension to derive encryption keys from passkeys
- Requires a relying party server (can be self-hosted cheaply)

**Complexity:** Hard (requires backend server)
**CPU impact:** Negligible (client-side)
**Dependencies:** `passkeys`

---

### P4-4: Self-hosted sync server (Rust axum)

**Approach:**
- Rust axum server with LWW JSON sync (as designed in P3-4)
- Deploy on cheap VPS or self-hosted hardware
- Client-side: `dart` HTTP client with outbox + pull pattern
- Zero-knowledge: server never sees plaintext (E2E encrypted)

**Complexity:** Hard (requires Rust backend + Flutter client)
**CPU impact:** N/A (server-side)
**Dependencies:** Rust toolchain (runs on GitHub Actions for server build)

---

### P4-5: Web collaborative editing (deferred until Automerge FFI is stable)

**Approach:**
- `dart_automerge` FFI for CRDT-based concurrent editing
- Requires a sync server (P4-4)
- **Deferred** until Automerge FFI is production-ready

**Complexity:** Hard
**CPU impact:** N/A (server-side)
**Dependencies:** `dart_automerge`

---

## Plugin / integration feasibility summary

| Tool | Integration Type | Integration Strategy | Recommendation |
|---|---|---|---|
| **LocalSend** | **Core Feature** | Native Dart REST client using `http` over local WiFi. | **Highly Recommended**: Core feature for P2P local note sharing without cloud dependencies. |
| **Markdown & LaTeX** | **Core Feature** | Rendered inline via `flutter_markdown_plus` and `ratex_flutter` (FFI). | **Highly Recommended**: Core feature for academic, math, developer, and code-based notes. |
| **PDF24 (PDF Tools)** | **Core Feature** | Natively merge/split using pure Dart `pdf` or `pdf_utils` libraries. | **Recommended**: Core feature for manipulating slides, lecture notes, or combined pages. |
| **Tesseract OCR** | **Optional Plugin** | Loaded dynamically on demand with bundled engine binaries and language data. | **Recommended as Plugin**: Dynamically loaded only when needed to keep the base app binary lightweight. |
| **LibreOffice** | **Optional Plugin** | `libre_office_kit_converter` plugin installed dynamically or only on mobile/desktop. | **Recommended as Plugin**: LibreOffice binaries add >600MB, so keeping it optional is critical. |
| **Bitwarden** | **External Integration** | Launch vault apps or programmatic local API (`bw serve`) via `url_launcher`. | **Recommended as Integration**: Delegate secure password storage to dedicated managers. |
| **7-Zip** | **Core Feature** | Bundled ZIP/Tar compression via pure Dart `archive` package. | **Highly Recommended**: Core feature for database exports and backups. |
| **ProtonVPN** | **Declined** | No integration planned. | VPN utility is out of scope for a local-first note-taking app. |
| **HandBrake** | **Declined** | No integration planned; use native light compressor. | Video notes can use standard `video_compress` rather than bulky external codecs. |

---

## GitHub Actions optimization notes

Heavy tasks that should run in CI (not locally):
- **PDF rendering tests** — headless, no display needed
- **OCR processing** — run in CI with test images
- **Release APK build** — `flutter build apk --release`
- **Web build** — `flutter build web --profile`
- **Database migration tests** — headless Dart
- **Version diff/compression tests** — pure Dart

Tasks that are too heavy for this CPU and should use CI:
- **PDF rendering of large documents** (50+ pages)
- **Video compression** (CPU-intensive)
- **OCR on large image batches**
- **Release APK signing** (needs keystore, not local)

---

## Dependency budget (FOSS/free only)

All packages below are free for commercial use and open-source:

| Package | License | Purpose |
|---|---|---|
| `drift` + `drift_flutter` | MIT | SQLite database |
| `pdfrx` | BSD-3 | PDF rendering |
| `cryptography` | BSD-3 | Encryption (AES-256-GCM, Argon2id) |
| `flutter_secure_storage` | MIT | Key storage |
| `flex_color_picker` | MIT | Color picker with recent colors |
| `flutter_markdown_plus` | MIT | Markdown rendering |
| `ratex_flutter` | MIT | LaTeX rendering |
| `tesseract_ocr` | Apache 2.0 | On-device OCR |
| `archive` | MIT | ZIP/gzip/tar compression |
| `pdf` | MIT | PDF generation |
| `share_plus` | MIT | OS share sheet |
| `flutter_biometric_auth_plus` | MIT | Biometric auth (all platforms incl. web) |
| `flutter_auth_screen` | MIT | PIN entry UI |
| `home_widget` | MIT | Home screen widgets |
| `http` | MIT | HTTP client (for LocalSend, Bitwarden API) |
| `video_compress` | MIT | Video compression |
| `diff_match_patch` | Apache 2.0 | Text diffing |
| `file_picker` | MIT | File picking |
| `intl` | BSD-3 | Date/time formatting |
| `uuid` | MIT | UUID generation |

---

## Implementation order (recommended)

1. **P2-1** Multipage PDF import (highest user impact, medium complexity)
2. **P2-3** Markdown support (easy, high value)
3. **P2-4** Custom brushes + color picker (medium, visible quality improvement)
4. **P2-6** Tags (easy, organizes notes beyond hierarchy)
5. **P2-7** Fuzzy search (medium, makes the app feel professional)
6. **P2-9** Export + share (medium, enables real-world usage)
7. **P3-1** E2E encryption (medium, critical for privacy-focused positioning)
8. **P3-2** Biometric auth (easy, adds security feel)
9. **P3-3** Encrypted backup (medium, data safety)
10. **P3-6** OCR (medium, makes notes searchable)
11. **P3-7** Markdown + LaTeX (easy, academic appeal)
12. **P4-1** Diagramming (medium, premium feel)
13. **P4-2** Home screen widgets (hard, platform integration)
14. **P4-4** Self-hosted sync (hard, multi-device)

---

## Deferred (explicitly)

- Cloud OCR (requires server infrastructure)
- Web collaborative editing (deferred until Automerge FFI is stable)
- iOS (requires Mac + Xcode, not available in this environment)
- SQLCipher full-DB encryption (web doesn't support it; use note-level E2E instead)
- Custom Rust via `flutter_rust_bridge` (deferred until sync server is needed)
- Passphrase recovery (requires secure server-side key escrow)
- ProtonVPN integration (no meaningful API; use generic VPN instead)
- HandBrake integration (use native `video_compress` instead)
