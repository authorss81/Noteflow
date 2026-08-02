import 'dart:convert';

import 'package:drift/drift.dart';

import 'database.dart' hide Notebook, Section;
import '../models/note_models.dart';
import '../models/stroke.dart';

/// High-level access to notes data, abstracting the database.
class NoteRepository {
  final AppDatabase _db;
  NoteRepository(this._db);

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
    return rows
        .map((p) => NotePage(
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
            ))
        .toList();
  }

  Future<NotePage> createPage({
    required String sectionId,
    String title = 'Untitled',
    String? sourceFilePath,
    String? sourceFileType,
    int pageIndex = 0,
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
    );
    await _db.insertPage(PagesCompanion.insert(
      id: p.id,
      sectionId: p.sectionId,
      title: p.title,
      sourceFilePath: Value(p.sourceFilePath),
      sourceFileType: Value(p.sourceFileType),
      pageIndex: Value(p.pageIndex),
      createdAt: p.createdAt,
      updatedAt: p.updatedAt,
    ));
    return p;
  }

  Future<NotePage?> page(String id) async {
    final p = await _db.pageById(id);
    if (p == null) return null;
    return NotePage(
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
    );
  }

  Future<void> renamePage(String id, String title) async {
    await (_db.update(_db.pages)..where((t) => t.id.equals(id)))
        .write(PagesCompanion(title: Value(title)));
  }

  Future<void> togglePin(String id, bool pinned) => _db.togglePin(id, pinned);

  Future<void> trashPage(String id) => _db.softDeletePage(id);

  // ---- Strokes content ----
  Future<List<Stroke>> strokesFor(String pageId) async {
    final json = await _db.contentFor(pageId);
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
    await _db.saveContent(pageId, encodeStrokes(strokes));
    await _db.touchPage(pageId);
  }

  // ---- Versions ----
  Future<void> snapshot(String pageId, String strokesJson, {String label = ''}) async {
    await _db.insertVersion(PageVersionsCompanion.insert(
      id: _id(),
      pageId: pageId,
      strokesJson: strokesJson,
      label: Value(label),
      createdAt: DateTime.now(),
    ));
    await _db.pruneVersions(pageId, 100);
  }

  Future<List<PageVersion>> versions(String pageId) => _db.versionsFor(pageId);

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

  String _id() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}
