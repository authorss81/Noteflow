# Noteflow — Detailed Roadmap

> Last updated: 2026-08-03
> Hardware constraint: AMD Athlon 200GE (2C/4T, ~2.7 GB free RAM)
> Build strategy: cloud builds via GitHub Actions (no local Android SDK)
> All dependencies must be FOSS or free for commercial use.

---

## Status summary

| Phase | Status |
|---|---|
| P0 — Make it actually work | ✅ done |
| P1 — Usable day-to-day | ✅ done |
| P2 — Real annotation app | 🟡 partially done (see §Review) |
| P3 — Data safety & multi-device | 🟡 partially done (see §Review) |
| R1 — Immediate fixes & security hardening | 🔥 DO NOW (new phase) |
| E1 — Engagement / delight ("fun") | 🔄 planned after R1 |
| P4 — World-class | 📋 **moved LATER** |
| P5 — Platform & multi-device vision | 📋 **moved LATER** |

---

## § Independent review — Phase-by-phase audit (2026-08-03)

> Four parallel senior reviewers (Android dev, strictest code critic, competitor/product analyst, security pentester) plus competitive web research audited P1/P2/P3. Combined verdict below.

### What was reviewed
- **P0 (7/7): ✅ done** — PDF page-1 render, text import, lifecycle flush, autosave, versioning & restore all real.
- **P1 (10/10): ✅ done** — CRUD, trash, rename, autosave indicator, editor themes, empty states.
- **P2 (10 items):** 🟡 **partial** — export, templates, merge/split, version prune are real; **tags (P2-6) = SCHEMA ONLY / dead**, fuzzy search (P2-7) = title `LIKE` only, batch ops (P2-8) missing, formatting (P2-5) missing, brightness/contrast (P2-4) missing.
- **P3 (majority):** 🟡 **partial** — E2E encryption + biometrics + backup + P2P **exist but have serious security flaws** (§Security). P3-5 PDF tools, P3-6 OCR, P3-8 LibreOffice not real.

### Top findings (from all reviewers)
1. **Multi-page PDF imports each page as a separate note** — defeats the #1 marker use case. (confirmed `home_screen.dart:199-232`)
2. **Mobile "notebook click does nothing"** — the 3-level tree is rendered as 3 *sibling tabs*, so selection never navigates. (`home_screen.dart:2075-2093`)
3. **"Sections does nothing"** — every notebook auto-creates one `Quick Notes` section; no "move page between sections/notebooks"; taps only highlight. (`app_state.dart:190`, `home_screen.dart:1147`)
4. **`select`/pan tool unreachable** → pinch-zoom & drag-pan gestures disabled in the canvas. (`annotation_canvas.dart:211-212`, `editor_screen.dart:692-699`)
5. **Search is title-only** — no content / tag / OCR search, no FTS5.
6. **Search engine/OCR is FAKE** — OCR returns hard-coded strings for titles containing "invoice"/"receipt"; plugin "downloads" are simulated. Trust killer.
7. **CRITICAL (strict-critic): Master Password can never be enabled** — `_uuid().codeUnits.sublist(0,16)` RangeErrors (10-char string) swallowed → `setMasterPassword` always false. E2E + lock unreachable.
8. **CRITICAL (strict-critic): Theme system never applied** — `MaterialApp` sets no `theme`/`themeMode`; 4 theme modes are decorative.
9. **CRITICAL (Android): release signed with debug keystore + placeholder `com.yourname.noteflow`** → not publishable; `allowBackup` unset (=true); heavy imports/autosave on UI isolate → OOM/ANR; startup blocks first frame.
7. **Security Criticals** — release signed with debug keystore; PBKDF2=1000 iterations; timestamp-derived salt; raw master password persisted for biometrics; **Zip-Slip path traversal in backup restore**; unauthenticated cleartext HTTP P2P listener on 0.0.0.0. (full list below)

See **§R1** for the prioritized fixes, **§E1** for engagement/delight UX work.

---

## Phase R1 — Immediate fixes & critical hardening (DO NOW)

### R1-CRITICAL SECURITY (must fix before any release)
| ID | Sev | Fix | File:line |
|---|---|---|---|
| R1-1 | 🔴 Critical | ✅ done — **Stop signing release with debug keystore** → private release keystore via `key.properties`, keep out of VCS | `android/app/build.gradle.kts:28-32` |
| R1-2 | 🔴 Critical | ✅ done — Raise KDF to **Argon2id** (≥19 MiB, ≥2 passes) or PBKDF2 ≥600,000; track it in metadata | `encryption_service.dart:11` |
| R1-3 | 🔴 Critical | ✅ done — Use **CSPRNG salt** (not timestamp `codeUnits`) | `app_state.dart:296,306,328` |
| R1-4 | 🔴 Critical | ✅ done — **No master-password-in-keystore for biometrics** → biometric-bound key wrapping the DEK | `app_state.dart:348` |
| R1-5 | 🔴 Critical | ✅ done — **Zip-Slip fix in backup restore** — sanitize/`canonicalize/allowlist archive entry names, block `..`/absolute | `home_screen.dart:464-478` |
| R1-6 | 🔴 Critical | ✅ done — Enable **R8/ProGuard `isMinifyEnabled` + `shrinkResources`** + `proguard-rules.pro` | `android/app/build.gradle.kts` |

### R1-BLOCKING BUGS (silently dead features — add to do-now priority)
| ID | Sev | Bug | Fix | File:line |
|---|---|---|---|---|
| R1-30 | 🔴 Critical | ✅ done — **Master Password can NEVER be enabled.** `_uuid()` returns a 10-char base36 string; `.codeUnits.sublist(0,16)` on a 10-element list throws `RangeError`, swallowed by `catch` → `setMasterPassword` always `false`. Whole E2E + lock unreachable. | CSPRNG 16-byte salt, base64 encode/decode | `app_state.dart:296,306-320` |
| R1-31 | 🔴 Critical | ✅ done — **Theming is wired to nothing.** `MaterialApp` sets **no `theme:`/`darkTheme:`/`themeMode:`** — `AppTheme`/`PaperPalette` unused; the 4 theme modes never change the UI; theme menus are decorative. | Bind `theme`, `darkTheme`, `themeMode` in `main.dart` | `main.dart:34-40`, `app_theme.dart` |
| R1-32 | 🔴 Critical | **Cross-check R1-3/R1-2 are live:** the salt bug (this R1-1) also breaks `R1-3`'s CSPRNG fix silently. | complete CSPRNG + KDF fix | (see R1-1/2/3) |

### R1-HIGH (must fix before marketing "private")
7. ✅ done — Wire `SecurityService` (Keystore DEK) — was **dead code**; DEK now persisted/read via keystore-backed `SecurityService` (R1-7/R1-4). (`security_service.dart`, `app_state.dart:22`)
8. ✅ done — Remove plaintext verifier oracle; wrong password detected via DEK-unwrap GCM auth failure. (`app_state.dart:301-311`)
9. ✅ done — Automatically lock on background + inactivity timeout; `_repo.encryptionKey` cleared on background. (`main.dart:37`, `app_state.dart`)
10. ✅ done — Encrypt metadata (titles, notebook names, tags) + imported source files at rest; legacy plaintext migrated on first unlock; search now in-memory. (`repository.dart`, `database.dart`, `import_service.dart`)
11. ✅ done — Harden P2P: no wildcard CORS (dropped; native clients), one-time UDP-pong handshake token required on every POST, 5 MB body cap, DEK-encrypted payload when a master password exists (rejected while vault locked), `usesCleartextTraffic` for LAN. (`p2p_share_service.dart`, `app_state.dart`, `AndroidManifest.xml`)
12. ✅ done — Add `INTERNET` permission to **main** manifest (was debug-only → P2P silently failed in release); `USE_BIOMETRIC` already merged via `local_auth_android`. (`android/app/src/main/AndroidManifest.xml`)
13. ✅ done — **Placeholder `applicationId`/`namespace` `com.yourname.noteflow`** replaced with globally unique `com.authorss81.noteflow` (do not change again). (`android/app/build.gradle.kts:8,19`, `MainActivity.kt`)
14. ✅ done — **`android:allowBackup` unset (=true)** → `allowBackup="false"` + `fullBackupContent="false"` + `data_extraction_rules` excluding root/file/database/sharedpref/external. (`AndroidManifest.xml`, `res/xml/data_extraction_rules.xml`)
15. 🟡 partial — **Heavy work on the UI isolate** → ANR/jank & OOM: ✅ capped PDF render to 1600px long edge (no more native-res OOM), ✅ `ui.Image.dispose()` after PNG write in import; still TODO: isolate-offload of `loadPdfPages`/PNG encode (needs on-device verification — pdfrx isolate-safety), `file_picker withData:false`, autosave is already 400ms trailing-edge debounced. (`import_service.dart`, `home_screen.dart:199-236`)
16. ✅ done — **Startup blocks first frame**: `runApp` now happens immediately; `bootstrap()` (DB open + tree load + P2P server bind) runs in the background with a splash until `loaded`, and marks loaded even on failure. (`main.dart:12-21`, `app_state.dart:106-126`)
17. **`allowBackup`/metadata plaintext** also breaks Play Data-safety honesty (see R1-10/14).

### R1-LOW (fix when convenient)
18. ✅ done (moot) — Sanitize LIKE `%`/`_` in search — search is now in-memory title matching (R1-10), no SQL LIKE. Debounce search ~300 ms (`home_screen.dart:1503`).
19. Restrict remote images in Markdown (`imageBuilder`) to stop external fetches. (`markdown_preview_screen.dart:97`)
20. Don't auto-copy note/OCR text to global clipboard; clear after delay. (`home_screen.dart:2044`)
21. Sanitize imported filenames for path traversal; only persist original PDF bytes if actually referenced. (`import_service.dart:37`, `home_screen.dart:198`)

### R1-FUNCTIONAL (core UX + correctness blockers)
22. **R1-22 · Multi-page PDF = one document.** Keep PDF as ONE `NotePage` with a page list (`pageIndex` already in schema), swipe/prev-next + page thumbnail strip; **"import as new doc vs insert"** option (GoodNotes/Notability parity). Kill per-page-note explosion **and orphaned original PDF** (each page gets its own PNG; the raw PDF file leaks on disk). Move rendering/PNG/file IO off the UI isolate. (`home_screen.dart:199-232`, `import_service.dart:121-187`)
23. **R1-23 Mobile drill-down navigation.** Replace 3 sibling tabs with Notebook → tap → sections → tap → pages, breadcrumb `Notebook / Section / Page`, `Icons.chevron_right` disclosure; **auto-navigate on select & auto-select newly created section** so the visible panel actually changes. Fix "click does nothing". (`home_screen.dart:2075-2093,935,1147`, `app_state.dart:171-213`)
24. **R1-24 Give Sections a purpose.** Remove forced single "Quick Notes"; "New section" CTA + empty-state explanation; highlight section in Pages header. (`app_state.dart:190`, `repository.dart:54-64`)
25. **R1-25 Restore reachable `select`/pan tool.** Add to toolbar so pinch-zoom/pan actually works — `panEnabled/scaleEnabled` only fire when `tool==StrokeTool.select`, which has NO visible button and no real select behavior. (`annotation_canvas.dart:211-212,445-446`, `editor_screen.dart:692-700,463-468`)
26. **R1-26 Add "Move to Section / Move to Notebook"** on page menu (needs repo `movePage` + refresh). (`home_screen.dart` page menu)
27. **R1-27 Add content search** — simple `WHERE strokesJson LIKE` on text strokes first; later FTS5 (`database.db`, `home_screen.dart`).
28. **R1-28 Rebuild import flow non-blocking** — progress sheet + per-file status + cancel + "PDF will create N pages" preview + undo; won't force-push last page. (`home_screen.dart:171-282`)
29. **R1-29 Kill fake OCR/plugins.** OCR returns hard-coded text ("Invoice #INV-2026", "Store: Noteflow Inc.") keyed on title; `downloadPlugin` is a fake progress timer. Implement real on-device OCR or remove; drop fake "downloads". (`home_screen.dart:2003-2059`, `plugin_loader_service.dart:16-65`)

### R1-CORRECTNESS (races, leaks, silent bugs)
- ✅ 30-36 done (`e4b1e6e` for 30-34, next commit for 35-36)
30. **File leaks on cascade delete.** ~~`deleteNotebook`/`deleteSection` → `db.deletePage` removes DB rows only, never the `imports/` files (only `emptyTrash`/per-page cleanup does).~~ ✅ Return deleted pages' `sourceFilePath`s and delete files. (`repository.dart:310-336`)
31. **P2P listener leak.** ~~`_setupP2pListener` `addListener` without `removeListener`.~~ ✅ `dispose`+remove. (`home_screen.dart`)
32. **`_reloadTree` async race.** ~~Overlapping reloads interleave.~~ ✅ Monotonic reload token. (`app_state.dart:168`)
33. **Autosave flush fire-and-forget in `dispose()`.** ~~unawaited, then `detach()` cancels timers.~~ ✅ flush captures page id before detach; pending writes survive. (`autosave_service.dart`)
34. **"Current version" highlight never works.** ~~`List<Stroke>` `==` identity.~~ ✅ normalized JSON compare. (`editor_screen.dart:812`)
35. **Random `_strokeId`/`_uuid` collisions** (µs timestamp) → PK conflicts / silent overwrite. ✅ shared CSPRNG 128-bit `newId()` (`lib/core/ids.dart`), used by stroke/notebook/section/page ids. (`annotation_canvas.dart`, `app_state.dart`, `repository.dart`)
36. **`exit(0)` after backup restore.** ~~hard-kill anti-pattern.~~ ✅ graceful `reloadAfterRestore()`: swap in fresh `AppDatabase`/`NoteRepository`, stop P2P, re-lock, re-bootstrap; master-password prefs kept so the existing password still unlocks the restored vault. (`app_state.dart`, `home_screen.dart:533`)

### R1-Release & CI
37. Replace placeholder `applicationId`; create prod keystore (`key.properties` secret in GH Actions); build **AAB** not just debug APK; pin `drift_dev` version; `-Xmx8G` in `gradle.properties` risks GitHub runner OOM → reduce to 4G.
38. Add a `flutter analyze` + `flutter test` gate (both workflows already call them); add a secrets scan.
39. Note: `flutter_secure_storage` on Windows/Linux may fall back to weaker storage — document/limit cross-platform.

**Definition of done for R1:**
- 🔴 Critical security fixed: no debug signing, no placeholder AppId, CSPRNG salt + Argon2id/PBKDF2≥600k, no master-password-in-keystore, Zip-Slip blocked, R8 enabled.
- 🔴 **Master Password actually enables** (R1-30) and **themes actually apply** (R1-31).
- No mock/fake features shipped (OCR/plugins real or removed).
- PDF stays one document; mobile drill navigates; sections usable; pan/zoom reachable; content search works; Critical races/leaks (R1-30..36) resolved.
- `flutter analyze` + `flutter test` clean.

---

## Phase E1 — UX & engagement ("make it delightful")

(Engagement/animation/animation/engagement + accessibility bar. Prioritized; start with cheap/low-risk.)

### E1-1 · Haptics (base writer feeling)
- `HapticFeedback.mediumImpact()` on page/section/notebook create + import complete; `lightImpact()` on undo/redo; pen-down/up snap. (`home_screen.dart:260,1251`; `annotation_canvas.dart:63,73,150-163`)

### E1-2 · Save celebrate (cheap, high perceived speed)
- On `saving → false`, `ScaleTransition` green check next to "Saved at HH:MM" + `selectionClick()`. (`editor_screen.dart:351-363`)

### E1-3 · Hero transitions page-list → editor
- `Hero(tag: 'page-$id')` on the page tile leading icon + matching Hero in editor AppBar → "hand holds paper". Use `PageRouteBuilder` fade-through for markdown preview too. (`home_screen.dart:1714-1717`)

### E1-4 · Animated empty states
- One shared `_EmptyState` widget: 56px icon + `TweenAnimationBuilder` scale-in w/ elastic `easeOutBack`; reuse for all 6 current bare-text empty states. (`home_screen.dart:897,1109,1545,1583,1647`)

### E1-5 · Animated toolbar tool-selection
- `AnimatedContainer` color 120ms + slight scale on tool select; share `AnimatedIcon` for active-tool. (`editor_screen.dart:667`)

### E1-6 · "Living ink" canvas feel
- In `_CanvasPainter`, smooth paths (cubic bezier) + a tip-dot that lags the pointer while pen down; make writing feel hand-drawn. (`annotation_canvas.dart`)

### E1-7 · Loading skeleton
- Replace flat `CircularProgressIndicator` on canvas load with a paper-skeleton shimmer (animated gradient over template). (`editor_screen.dart:471-472`)

### E1-8 · Animated micro-interactions
- Confetti/celebrate `CustomPainter` (no lib) on "Imported N pages" / "Pages merged"; page-restore ripple. (`home_screen.dart:1470-1478`)

### E1-9 · Pan/zoom scale feedback
- `AnimatedScale` scale/% indicator overlay ("80%") while panning/zooming. (`annotation_canvas.dart`)

### E1-ACCESSIBILITY (do alongside)
- Add `Semantics` container around canvas + `excludeFromSemantics` for raw paint; grow color swatches/toolbar to ≥48dp touch targets; unify success/failure feedback system (not just color). (`editor_screen.dart:657-707`; `annotation_canvas.dart:233-245`)

**Impact of E1:** adds psychological delight & an "award-grade canvas" feel; addresses the "emotionally flat" critique. Do E1-1..E1-5 first (cheap), E1-6..E1-9 next, E1-10 always.

---

## Phase P4 — World-class features («MOVED LATER»)

> These remain valuable but are after R1 + E1. Do they need backend server (P4-3/4) and macOS (widgets/collab) which are deferred here.

| Item | Scope | Deps / blockers |
|---|---|---|
| P4-1 Diagramming & mind maps | `flutter_flow_chart` + Mermaid via WebView | medium-hard, low CPU |
| P4-2 Home screen widgets | `home_widget`, `quick_actions`, WidgetKit | hard, requires iOS native |
| P4-3 Passkey auth | `passkeys` | needs relying-party server |
| P4-4 Self-hosted sync (Rust axum) | rust server + dart client | needs Rust toolchain; hard |
| P4-5 Web collab editing | `dart_automerge` | DEFERRED until FFI stable |

## Phase P5 — Platform & multi-device vision (MOVED LATER)

| Re | Scope | blockers |
|---|---|---|
| P5-1 Real on-device OCR (Tesseract) | build `tesseract_ocr` + `eng.traineddata`, background isolate | replaces fake mock; Medium CPU |
| P5-2 Self-hosted sync | see P4-4 | needs Rust backend |

*(Consolidated; other P2/P3 satellite items go into backlog: version diff, DB VACUUM, dark auto-detect, PDF24 tools, LibreOffice, Bitwarden, 7z in P3-list, video compress.)* — see Phase P3 backlog below.

---

## Phase P3 — Data safety & multi-device (existing backlog, mostly partial)

> Many P3 items partially ship (E2E, biometric, backup, P2P) but need the R1 hardening fixes first. Items not yet done remain here as backlog.

### P3-x remaining backlog
- P3-6 OCR (real) — see P5-1
- P3-8 LibreOffice DOCX→PDF — large native dep, optional plugin
- P3-9 Bitwarden Vault integration — external, optional
- P3-5 PDF24-style PDF tools
- P3-11 video compression
- P3-12/13... version diff, compression, VACUUM, dark auto — see P2/P the backlog below

---

## Phase P7 — Residual P2/P3 backlog (not priority)

Items that remain unimplemented from P2/P3, deferred but not removed:
- P2-5 text formatting (B/I/U)
- P2-7 FTS5 fuzzy search (title → content + tag)
- P2-8 batch ops (multi-select move/delete/tag)
- P2-11 word count/statistics
- P2-12 version diff/named checkpoints
- P2-13 lossless version compression
- P2-14 DB optimization (PRAGMA optimize, VACUUM, prune)
- P2-15 auto dark-mode (`ThemeMode.system`)
- P3-7 version merge (free checks offs), LaTeX
- P3-10 7-Zip exports

---

## Security findings — full audit register (from parallel pentest)

> All references built into the R1 tables above. Full register retained for traceability.

The security findings are tracked in §R1 with severity and file:line. Re-audit after fixing R1-1 through R1-16.

---

## Overview of engagement/UX system ("make it fun")
*(moved to E1 for build ordering — see Phase E1)*

---

## Previous planning (P2, P3 preserved for reference)

> Full original P2-1..P2-15 and P3-1..P3-11 + P4 detail restored below. It describes the **intended** behavior; **R1 supersedes where it conflicts** (notably R1-17: PDF should become ONE document instead of per-page notes).

### P2-1: Multipage PDF import (currently only page 1 renders)
**Problem:** `pdfrx` renders only the first page. Users importing multi-page PDFs see only page 1.
**Approach:**
- Iterate `PdfDocument.pages` (all pages, not just `.first`)
- For each page, render to an image via `page.render(width, height)` → `ui.decodeImageFromPixels`
- Create a separate `NotePage` per PDF page, each with the rendered image as background
- Store the original PDF bytes in `sourceFilePath` for re-rendering at higher quality if needed
**Complexity:** Medium
**CPU impact:** Low — single-threaded, fast on Athlon 200GE for 1–20 pages; 50+ pages → background isolate.
**Dependencies:** `pdfrx` (already imported)
> ⚠️ **REPLACED by R1-17** — a PDF should be ONE document with a page list (`pageIndex` already in schema), swipe/prev-next + thumbnail strip, with "import as new doc vs insert" option. Per-page-note explosion is a confirmed product bug.

---

### P2-2: Import as vector (PDF) vs pixel (images)
**Problem:** All imports are rasterized. Vector PDF data is lost.
**Approach:** PDF keep raw bytes + re-render on demand via `pdfrx`; store images on filesystem with `sourceFilePath`; add a `sourceFileType` column (pdf-vector / image-raster / text-plain).
**Complexity:** Easy/Easy | **Dep:** `image`

---

### P2-3: Markdown file support (.md import/preview)
**Approach:** Detect `.md`; parse with `markdown`; store raw + preview; render via `flutter_markdown_plus` in a read-only preview.
**Complexity:** Easy | **Dep:** `markdown`, `flutter_markdown_plus`
> ✅ Partially implemented (import/preview + editor "preview markdown" toggle).

---

### P2-4: Custom brushes, stroke width, brightness/contrast
**Approach:** stroke-width `Slider`; brightness/contrast via `ColorFilter.matrix()`; `flex_color_picker`; shape fill toggle.
**Complexity:** Medium | **Deps:** `flex_color_picker`
> 🟡 Partial — width + color picker done; **brightness/contrast & fill toggle missing.**

---

### P2-5: Text annotation formatting (bold, italic, underline)
**Approach:** when text tool active show B/I/U toggles; apply `TextStyle` to text strokes; store in `Stroke.textStyle`.
**Complexity:** Easy | **Dep:** none
> 🔴 Not implemented (`Stroke.textStyle` field absent).

---

### P2-6: Tags and categories
**Approach:** `tags` + `page_tags` junction; `Tag{id,name,color,createdAt}`; filter by tag; chips.
**Complexity:** Easy | **Deps:** none
> 🟡 SCHEMA ONLY — tables exist but **no repo methods, no UI, dead code.**

---

### P2-7: Fuzzy search across all notes
**Approach:** SQLite FTS5 virtual table `pages_fts USING fts5(content, title, tags)`; update index on save; debounced ranking.
**Complexity:** Medium | **Deps:** drift FTS5
> 🔴 Title-`LIKE` only. No content/tag/FTS. (R1-22 adds content search first.)

---

### P2-8: Batch operations (multi-select move/delete/tag)
**Approach:** long-press/checkbox multi-select; batch move/delete/tag in one transaction using `Set<String>`.
**Complexity:** Easy | **Dep:** none
> 🔴 Not implemented.

---

### P2-9: Export page as PNG/PDF + share
**Approach:** `RepaintBoundary.toImage()`→PNG; `pdf` package → PDF from canvas; `archive` → ZIP bundle; `share_plus` share sheet.
**Complexity:** Medium | **Deps:** `pdf`, `archive`, `share_plus`
> ✅ Implemented (per-page PNG/PDF + notebook/section merged PDF + share).

---

### P2-10: Page templates (blank, lined, grid, dot grid)
**Approach:** `Template{id,name,type,config}`; CustomPainter background; selectable on new page.
**Complexity:** Easy | **Dep:** none
> ✅ Implemented.

---

### P2-11: Word count / page statistics
**Approach:** token-count for text; stroke+annotation count for annotated; show in header/stats.
**Complexity:** Easy | **Dep:** none
> 🔴 Not implemented.

---

### P2-12: Version control features (checkpoints, diff, named versions)
**Approach:** named checkpoints (label field exists); diff serialized stroke JSON; visual diff highlight.
**Complexity:** Hard (diff) / Easy (naming) | **Dep:** `diff_match_patch`
> 🟡 autosave + restore + prune(100) exist; no diff/visual.

---

### P2-13: Lossless compression of version history
**Approach:** delta-encoding; `zlib`/`gzip`; prune policy; periodic `VACUUM`.
**Complexity:** Medium | **Dep:** `archive`
> 🔴 Not implemented.

---

### P2-14: Database optimization (VACUUM, compaction, pruning)
**Approach:** `PRAGMA optimize` at startup; version retention policy; background `VACUUM`; indexes.
**Complexity:** Medium | **Dep:** none
> 🔴 Not implemented.

---

### P2-15: Dark mode auto-detection (system theme)
**Approach:** `ThemeMode.system` + `didChangePlatformBrightness`; persist in Settings.
**Complexity:** Easy | **Dep:** none
> 🔴 Manual themes only.

---

### Phase P3 — original section content

#### P3-1: E2E encryption for notes
**Approach:** `cryptography`; Argon2id from password; AES-256-GCM; `flutter_secure_storage` for DEK (Android Keystore/iOS Keychain/DPAPI); Web Crypto API.
**Complexity:** Medium | **Deps:** `cryptography`, `flutter_secure_storage`
> 🟡 Exists (PBKDF2+AES-GCM + master password) but has Critical security flaws → **see R1-2..R1-4, R1-7.**

#### P3-2: Biometric authentication
**Approach:** `flutter_biometric_auth_plus` (all platforms incl. WebAuthn); PIN fallback `flutter_auth_screen`; auto-lock on background; Argon2id PIN hash.
**Complexity:** Easy–Medium | **Deps:** `flutter_biometric_auth_plus`, `flutter_auth_screen`
> ✅ Exists (local_auth, master-password-cached) but **stores raw password** for biometrics → **R1-4.**

#### P3-3: Secure backup/export with encryption
**Approach:** `.noteflow` ZIP (manifest + 5 tables + files/); AES-256-GCM w/ user password; Argon2id; decrypt→verify→extract.
**Complexity:** Medium | **Deps:** `archive`, `cryptography`
> ✅ Exists (ZIP + AES when master pw) but plaintext when no pw + **Zip-Slip** → **R1-5.**

#### P3-4: LocalSend integration (P2P)
**Approach:** LocalSend REST over HTTPS port 53317; Dart client; UDP discovery + upload/download over LAN.
**Complexity:** Medium | **Dep:** `http`
> 🟡 Custom P2P exists; unauthenticated cleartext → **R1-11.**

#### P3-5: PDF24-style PDF tools (merge, split, compress)
**Approach:** native `pdf_utils`/`pdf_manipulator`; PDF tools in import/export menu.
**Complexity:** Medium | **Deps:** `pdf_utils`/`pdf_manipulator`
> 🔴 Not implemented.

#### P3-6: OCR with Tesseract (searchable notes)
**Approach:** `tesseract_ocr` + `eng.traineddata` assets; background isolate; store `textContent`; search via FTS5.
**Complexity:** Medium | **Dep:** `tesseract_ocr`
> 🟡 **FAKE** — hard-coded strings for "invoice"/"receipt"; simulated downloads → **R1-24.**

#### P3-7: Markdown + LaTeX rendering
**Approach:** `flutter_markdown_plus`; `ratex_flutter` (FFI, no WebView).
**Complexity:** Easy | **Deps:** `flutter_markdown_plus`, `ratex_flutter`
> ✅ Partially — Markdown preview implemented (P3-7); LaTeX pending.

#### P3-8: LibreOffice DOCX→PDF
**Approach:** `libre_office_kit_converter_plugin`; DOCX/XLSX/PPTX→PDF offline; +600 MB only on Android/iOS.
**Complexity:** Medium–Hard | **Dep:** `libre_office_kit_converter_plugin`
> 🔴 Not real (DOCX handled only via naive `<w:t>` regex→markdown).

#### P3-9: Bitwarden vault integration
**Approach:** Vault Management (`bw serve`) for keys; `url_launcher` to open Bitwarden.
**Complexity:** Medium–Hard | **Dep:** `url_launcher`
> 🔴 Not implemented.

#### P3-10: 7-Zip / archive compression for exports
**Approach:** `archive` (ZIP/gzip/tar); `flutter_7zip` desktop for 7z.
**Complexity:** Easy | **Dep:** `archive`
> 🟡 zip only.

#### P3-11: HandBrake-style video compression
**Approach:** `video_compress`/`v_video_compressor` (NOT HandBrake).
**Complexity:** Easy | **Dep:** `video_compress`
> 🔴 Not implemented.

---

### Phase P4 — original section content (preserved)

#### P4-1: Diagramming & mind maps
**Approach:** `flutter_flow_chart`; Mermaid.js via WebView; `drawflow` JS via WebView.
**Complexity:** Medium–Hard | **Deps:** `flutter_flow_chart`, WebView | 🔴 later

#### P4-2: Home screen widgets
**Approach:** `home_widget`, `quick_actions`; recent title + quick-create; ShortcutManager / WidgetKit.
**Complexity:** Hard | **Deps:** `home_widget`, `quick_actions`
> Deferred (iOS native required).

#### P4-3: Passkey-based authentication (WebAuthn/FIDO2)
**Approach:** `passkeys`; PRF → encryption keys; needs relying-party server.
**Complexity:** Hard | **Deps:** `passkeys`
> Deferred (needs backend).

#### P4-4: Self-hosted sync server (Rust axum)
**Approach:** axum LWW JSON sync as designed in P3-4; deploy on VPS; dart outbox+pull; zero-knowledge.
**Complexity:** Hard | **Deps:** Rust toolchain.

#### P4-5: Web collaborative editing
**Approach:** `dart_automerge` FFI CRDT; require P4-4. **Deferred until FFI stable.**
**Complexity:** Hard.

---

### Plugin / integration feasibility summary

| Tool | Integration Type | Strategy | Recommendation |
|---|---|---|---|
| LocalSend | Core Feature | Native Dart REST client over local WiFi | **High rec.** P2P local sharing, no cloud |
| Markdown & LaTeX | Core Feature | `flutter_markdown_plus` + `ratex_flutter` | **High rec.** academic/dev notes |
| PDF24 (PDF tools) | Core Feature | pure-Dart `pdf`/`pdf_utils` merge/split | **Rec.** slides, mixed pages |
| Tesseract OCR | Optional Plugin | on-demand engine + language data | **Rec. as Plugin** keep binary light |
| LibreOffice | Optional Plugin | `libre_office_kit_converter` on mobile/desktop | **Rec. as Plugin** >600 MB |
| Bitwarden | External Integration | `url_launcher`/`bw serve` | **Rec. as Integration** |
| 7-Zip | Core Feature | pure-Dart `archive` | **High rec** exports/backups |
| ProtonVPN | Declined | none | VPN out of scope |
| HandBrake | Declined | none; `video_compress` | Out of scope |

---

### GitHub Actions optimization notes (preserved)
Heavy CI-only: PDF render tests, OCR processing, Release APK build (**+ release keystore secret**), Web build, DB migration tests, version diff/compression tests. Too heavy for CPU, use CI: large PDFs, video compression, large OCR batches, release APK signing.

### Dependency budget (FOSS/free only)
`drift`+`drift_flutter` (MIT) · `pdfrx` (BSD-3) · `cryptography` (BSD-3) · `flutter_secure_storage` (MIT) · `flex_color_picker` (MIT) · `flutter_markdown_plus` (MIT) · `ratex_flutter` (MIT) · `tesseract_ocr` (Apache-2.0) · `archive` (MIT) · `pdf` (MIT) · `share_plus` (MIT) · `flutter_biometric_auth_plus` (MIT) · `flutter_auth_screen` (MIT) · `home_widget` (MIT) · `http` (MIT) · `video_compress` (MIT) · `diff_match_patch` (Apache-2.0) · `file_picker` (MIT) · `intl` (BSD-3) · `uuid` (MIT).

### Deferred (explicitly)
Cloud OCR (needs server) · Web collab editing (Automerge FFI unstable) · iOS (needs Mac/Xcode) · SQLCipher full-DB (unsupported on web) · `flutter_rust_bridge` (until sync needed) · Passphrase recovery (needs key escrow server) · ProtonVPN · HandBrake (use `video_compress`).

---

## Open questions / edge cases
- **Multi-page doc model** — normalize `pageIndex` & navigation into a `Document`/`NotePage` grouping; confirm schema migration.
- **Autosave cadence** with many separate pages importing; throttling.
- **Backup format versioning** to remain Zip-Slip-safe across older backups.
- **CI signing** — add encrypted keystore secret to GitHub Actions, set `release` signing in workflow.

---