import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:cryptography/cryptography.dart';

import 'database.dart' hide Notebook, Section;
import 'database.dart' as drift;
import '../models/note_models.dart';
import '../models/stroke.dart';
import '../services/import_service.dart';
import '../services/encryption_service.dart';
import '../core/ids.dart';

/// High-level access to notes data, abstracting the database.
class NoteRepository {
  final AppDatabase _db;
  SecretKey? encryptionKey;

  NoteRepository(this._db);

  /// Prefix marking an at-rest-encrypted metadata value (R1-10). Values that
  /// don't carry this prefix are treated as legacy plaintext, which keeps
  /// pre-encryption databases readable until [migrateLegacyMetadata] rewrites
  /// them.
  static const _metaPrefix = 'enc:v1:';

  Future<String> _encryptMeta(String? plain) async {
    final key = encryptionKey;
    if (key == null || plain == null || plain.isEmpty) return plain ?? '';
    if (plain.startsWith(_metaPrefix)) return plain;
    return '$_metaPrefix${await EncryptionService.encrypt(plain, key)}';
  }

  Future<String> _decryptMeta(String? stored) async {
    if (stored == null || stored.isEmpty) return stored ?? '';
    if (!stored.startsWith(_metaPrefix)) return stored;
    final key = encryptionKey;
    if (key == null) return stored;
    try {
      return await EncryptionService.decrypt(
          stored.substring(_metaPrefix.length), key);
    } catch (_) {
      return stored;
    }
  }

  Future<void> closeDatabase() => _db.close();

  // ---- Notebooks / Sections ----
  Future<List<Notebook>> notebooks() async {
    final rows = await _db.allNotebooks();
    final result = <Notebook>[];
    for (final n in rows) {
      result.add(Notebook(
          id: n.id,
          name: await _decryptMeta(n.name),
          createdAt: n.createdAt));
    }
    return result;
  }

  Future<Notebook> ensureDefaultNotebook() async {
    final existing = await notebooks();
    if (existing.isNotEmpty) return existing.first;
    final nb = Notebook(
      id: _id(),
      name: 'My Notebook',
      createdAt: DateTime.now(),
    );
    await _db.insertNotebook(NotebooksCompanion.insert(
      id: nb.id,
      name: await _encryptMeta(nb.name),
      createdAt: nb.createdAt,
    ));
    return nb;
  }

  Future<List<Section>> sections(String notebookId) async {
    final rows = await _db.sectionsFor(notebookId);
    final result = <Section>[];
    for (final s in rows) {
      result.add(Section(
          id: s.id,
          notebookId: s.notebookId,
          name: await _decryptMeta(s.name),
          createdAt: s.createdAt));
    }
    return result;
  }

  Future<Section> ensureDefaultSection(String notebookId) async {
    final existing = await sections(notebookId);
    if (existing.isNotEmpty) return existing.first;
    final s = Section(
      id: _id(),
      notebookId: notebookId,
      name: 'Quick Notes',
      createdAt: DateTime.now(),
    );
    await _db.insertSection(SectionsCompanion.insert(
      id: s.id,
      notebookId: s.notebookId,
      name: await _encryptMeta(s.name),
      createdAt: s.createdAt,
    ));
    return s;
  }

  // ---- Pages ----
  Future<List<NotePage>> pages(String sectionId) async {
    final rows = await _db.pagesFor(sectionId);
    final result = <NotePage>[];
    for (final r in rows) {
      result.add(await _pageFromRow(r));
    }
    return result;
  }

  Future<NotePage> createPage({
    required String sectionId,
    String title = 'Untitled',
    String? sourceFilePath,
    String? sourceFileType,
    int pageIndex = 0,
    String? template,
  }) async {
    final now = DateTime.now();
    final p = NotePage(
      id: _id(),
      sectionId: sectionId,
      title: title,
      sourceFilePath: sourceFilePath,
      sourceFileType: sourceFileType,
      pageIndex: pageIndex,
      createdAt: now,
      updatedAt: now,
      template: template,
    );
    await _db.insertPage(drift.PagesCompanion.insert(
      id: p.id,
      sectionId: p.sectionId,
      title: await _encryptMeta(p.title),
      sourceFilePath: Value(p.sourceFilePath),
      sourceFileType: Value(p.sourceFileType),
      pageIndex: Value(p.pageIndex),
      createdAt: p.createdAt,
      updatedAt: p.updatedAt,
      template: Value(p.template),
    ));
    return p;
  }

  Future<NotePage?> page(String id) async {
    final p = await _db.pageById(id);
    return p == null ? null : _pageFromRow(p);
  }

  Future<void> renamePage(String id, String title) async {
    await (_db.update(_db.pages)..where((t) => t.id.equals(id)))
        .write(PagesCompanion(title: Value(await _encryptMeta(title))));
  }

  Future<void> togglePin(String id, bool pinned) => _db.togglePin(id, pinned);

  Future<void> trashPage(String id) => _db.softDeletePage(id);

  Future<void> restorePage(String id) => _db.restorePage(id);

  Future<List<NotePage>> trashedPages() async {
    final rows = await _db.trashedPages();
    final result = <NotePage>[];
    for (final r in rows) {
      result.add(await _pageFromRow(r));
    }
    return result;
  }

  Future<List<NotePage>> searchPages(String query) async {
    // Titles are encrypted at rest, so SQL LIKE can't be used (R1-10). Decrypt
    // all active titles and match in memory. This also sidesteps LIKE wildcard
    // injection from `%`/`_`.
    final rows = await _db.allActivePages();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final result = <NotePage>[];
    for (final r in rows) {
      final title = (await _decryptMeta(r.title)).toLowerCase();
      if (title.contains(q)) result.add(await _pageFromRow(r));
    }
    return result;
  }

  Future<void> renameNotebook(String id, String name) async =>
      _db.renameNotebook(id, await _encryptMeta(name));
  Future<void> renameSection(String id, String name) async =>
      _db.renameSection(id, await _encryptMeta(name));

  /// Permanently deletes every trashed page (and their imported files).
  Future<void> emptyTrash() async {
    final trashed = await trashedPages();
    for (final p in trashed) {
      await deletePage(p.id, sourceFilePath: p.sourceFilePath);
    }
  }

  Future<NotePage> _pageFromRow(drift.Page p) async => NotePage(
        id: p.id,
        sectionId: p.sectionId,
        title: await _decryptMeta(p.title),
        sourceFilePath: p.sourceFilePath,
        sourceFileType: p.sourceFileType,
        pageIndex: p.pageIndex,
        createdAt: p.createdAt,
        updatedAt: p.updatedAt,
        pinned: p.pinned,
        deleted: p.deleted,
        template: p.template,
      );

  // ---- Strokes content ----
  Future<List<Stroke>> strokesFor(String pageId) async {
    var json = await _db.contentFor(pageId);
    if (json != null && json.isNotEmpty && encryptionKey != null) {
      if (!json.trim().startsWith('[')) {
        try {
          json = await EncryptionService.decrypt(json, encryptionKey!);
        } catch (_) {
          return [];
        }
      }
    }
    return decodeStrokes(json);
  }

  List<Stroke> decodeStrokes(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final list = (jsonDecode(json) as List).cast<Map<String, Object?>>();
      return list.map(Stroke.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  String encodeStrokes(List<Stroke> strokes) =>
      jsonEncode(strokes.map((s) => s.toJson()).toList());

  Future<void> saveStrokes(String pageId, List<Stroke> strokes) async {
    var rawJson = encodeStrokes(strokes);
    if (encryptionKey != null) {
      rawJson = await EncryptionService.encrypt(rawJson, encryptionKey!);
    }
    await _db.saveContent(pageId, rawJson);
    await _db.touchPage(pageId);
  }

  // ---- Versions ----
  Future<void> snapshot(String pageId, String strokesJson, {String label = ''}) async {
    var finalJson = strokesJson;
    if (encryptionKey != null && strokesJson.trim().startsWith('[')) {
      finalJson = await EncryptionService.encrypt(strokesJson, encryptionKey!);
    }
    await _db.insertVersion(drift.PageVersionsCompanion.insert(
      id: _id(),
      pageId: pageId,
      strokesJson: finalJson,
      label: Value(label),
      createdAt: DateTime.now(),
    ));
    await _db.pruneVersions(pageId, 100);
  }

  Future<List<PageVersion>> versions(String pageId) => _db.versionsFor(pageId);

  Future<List<PageVersion>> decryptedVersions(String pageId) async {
    final raw = await versions(pageId);
    final decrypted = <PageVersion>[];
    for (final v in raw) {
      var json = v.strokesJson;
      if (encryptionKey != null && !json.trim().startsWith('[')) {
        try {
          json = await EncryptionService.decrypt(json, encryptionKey!);
        } catch (_) {}
      }
      decrypted.add(PageVersion(
        id: v.id,
        pageId: v.pageId,
        strokesJson: json,
        label: v.label,
        createdAt: v.createdAt,
      ));
    }
    return decrypted;
  }

  Future<void> insertNotebook(Notebook n) async =>
      _db.insertNotebook(NotebooksCompanion.insert(
        id: n.id,
        name: await _encryptMeta(n.name),
        createdAt: n.createdAt,
      ));

  Future<void> insertSection(Section s) async =>
      _db.insertSection(SectionsCompanion.insert(
        id: s.id,
        notebookId: s.notebookId,
        name: await _encryptMeta(s.name),
        createdAt: s.createdAt,
      ));

  Future<void> deleteNotebook(String id) async {
    // Collect imported files first: cascade delete removes rows only, never
    // the files in imports/ (CORR-30).
    final paths = <String>[];
    for (final s in await _db.sectionsFor(id)) {
      for (final p in await _db.pagesFor(s.id, includeDeleted: true)) {
        final f = p.sourceFilePath;
        if (f != null) paths.add(f);
      }
    }
    await _db.deleteNotebook(id);
    await _deleteStoredFiles(paths);
  }

  Future<void> deleteSection(String id) async {
    final pages = await _db.pagesFor(id, includeDeleted: true);
    final paths =
        pages.map((p) => p.sourceFilePath).whereType<String>().toList();
    await _db.deleteSection(id);
    await _deleteStoredFiles(paths);
  }

  Future<void> _deleteStoredFiles(List<String> paths) async {
    for (final path in paths) {
      await ImportService().deleteStoredFile(path);
    }
  }

  /// One-time migration that rewrites any legacy plaintext metadata (notebook
  /// names, section names, page titles, tag names) to DEK-encrypted form.
  /// Called after the first successful unlock once a master password exists
  /// (R1-10).
  Future<void> migrateLegacyMetadata() async {
    for (final n in await _db.allNotebooks()) {
      if (n.name.isEmpty || n.name.startsWith(_metaPrefix)) continue;
      await _db.renameNotebook(n.id, await _encryptMeta(n.name));
    }
    for (final s in await _db.allSections()) {
      if (s.name.isEmpty || s.name.startsWith(_metaPrefix)) continue;
      await _db.renameSection(s.id, await _encryptMeta(s.name));
    }
    for (final p in await _db.allActivePages()) {
      if (p.title.isEmpty || p.title.startsWith(_metaPrefix)) continue;
      await (_db.update(_db.pages)..where((t) => t.id.equals(p.id)))
          .write(PagesCompanion(title: Value(await _encryptMeta(p.title))));
    }
    for (final t in await _db.allTags()) {
      if (t.name.isEmpty || t.name.startsWith(_metaPrefix)) continue;
      await _db.renameTag(t.id, await _encryptMeta(t.name));
    }
  }

  /// Permanently deletes a page, also removing its imported source file.
  Future<void> deletePage(String id, {String? sourceFilePath}) async {
    await _db.deletePage(id);
    if (sourceFilePath != null) {
      await ImportService().deleteStoredFile(sourceFilePath);
    }
  }

  String _id() => newId();
}
