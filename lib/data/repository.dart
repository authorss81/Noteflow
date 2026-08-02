import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:cryptography/cryptography.dart';

import 'database.dart' hide Notebook, Section;
import 'database.dart' as drift;
import '../models/note_models.dart';
import '../models/stroke.dart';
import '../services/import_service.dart';
import '../services/encryption_service.dart';

/// High-level access to notes data, abstracting the database.
class NoteRepository {
  final AppDatabase _db;
  SecretKey? encryptionKey;

  NoteRepository(this._db);

  Future<void> closeDatabase() => _db.close();

  // ---- Notebooks / Sections ----
  Future<List<Notebook>> notebooks() async {
    final rows = await _db.allNotebooks();
    return rows
        .map((n) => Notebook(id: n.id, name: n.name, createdAt: n.createdAt))
        .toList();
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
      name: nb.name,
      createdAt: nb.createdAt,
    ));
    return nb;
  }

  Future<List<Section>> sections(String notebookId) async {
    final rows = await _db.sectionsFor(notebookId);
    return rows
        .map((s) => Section(
            id: s.id, notebookId: s.notebookId, name: s.name, createdAt: s.createdAt))
        .toList();
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
      name: s.name,
      createdAt: s.createdAt,
    ));
    return s;
  }

  // ---- Pages ----
  Future<List<NotePage>> pages(String sectionId) async {
    final rows = await _db.pagesFor(sectionId);
    return rows.map(_pageFromRow).toList();
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
      title: p.title,
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
        .write(PagesCompanion(title: Value(title)));
  }

  Future<void> togglePin(String id, bool pinned) => _db.togglePin(id, pinned);

  Future<void> trashPage(String id) => _db.softDeletePage(id);

  Future<void> restorePage(String id) => _db.restorePage(id);

  Future<List<NotePage>> trashedPages() async {
    final rows = await _db.trashedPages();
    return rows.map(_pageFromRow).toList();
  }

  Future<List<NotePage>> searchPages(String query) async {
    final rows = await _db.searchPages(query);
    return rows.map(_pageFromRow).toList();
  }

  Future<void> renameNotebook(String id, String name) => _db.renameNotebook(id, name);
  Future<void> renameSection(String id, String name) => _db.renameSection(id, name);
  Future<void> deleteSection(String id) => _db.deleteSection(id);

  /// Permanently deletes every trashed page (and their imported files).
  Future<void> emptyTrash() async {
    final trashed = await trashedPages();
    for (final p in trashed) {
      await deletePage(p.id, sourceFilePath: p.sourceFilePath);
    }
  }

  NotePage _pageFromRow(drift.Page p) => NotePage(
        id: p.id,
        sectionId: p.sectionId,
        title: p.title,
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

  Future<void> insertNotebook(Notebook n) => _db.insertNotebook(NotebooksCompanion.insert(
        id: n.id,
        name: n.name,
        createdAt: n.createdAt,
      ));

  Future<void> insertSection(Section s) => _db.insertSection(SectionsCompanion.insert(
        id: s.id,
        notebookId: s.notebookId,
        name: s.name,
        createdAt: s.createdAt,
      ));

  Future<void> deleteNotebook(String id) => _db.deleteNotebook(id);

  /// Permanently deletes a page, also removing its imported source file.
  Future<void> deletePage(String id, {String? sourceFilePath}) async {
    await _db.deletePage(id);
    if (sourceFilePath != null) {
      await ImportService().deleteStoredFile(sourceFilePath);
    }
  }

  String _id() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}
