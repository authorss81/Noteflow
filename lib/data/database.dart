import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

class Notebooks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Sections extends Table {
  TextColumn get id => text()();
  TextColumn get notebookId => text().references(Notebooks, #id)();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Pages extends Table {
  TextColumn get id => text()();
  TextColumn get sectionId => text().references(Sections, #id)();
  TextColumn get title => text()();
  TextColumn get sourceFilePath => text().nullable()();
  TextColumn get sourceFileType => text().nullable()();
  IntColumn get pageIndex => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Serialized JSON array of [Stroke]s for a page.
class PageContent extends Table {
  TextColumn get pageId => text().references(Pages, #id)();
  TextColumn get strokesJson => text()();
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {pageId};
}

/// Immutable version snapshots for history/restore.
class PageVersions extends Table {
  TextColumn get id => text()();
  TextColumn get pageId => text().references(Pages, #id)();
  TextColumn get strokesJson => text()();
  TextColumn get label => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Tags for categorizing pages beyond the notebook/section hierarchy.
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get color => integer().withDefault(const Constant(0xFF1B365D))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Junction table linking pages to tags (many-to-many).
class PageTags extends Table {
  TextColumn get id => text()();
  TextColumn get pageId => text().references(Pages, #id)();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  Notebooks,
  Sections,
  Pages,
  PageContent,
  PageVersions,
  Tags,
  PageTags,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'noteflow',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.dart.js'),
      ),
    );
  }

  // ---- Notebooks ----
  Future<List<Notebook>> allNotebooks() =>
      (select(notebooks)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();

  Future<Notebook?> notebookById(String id) =>
      (select(notebooks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertNotebook(NotebooksCompanion n) =>
      into(notebooks).insertOnConflictUpdate(n);

  Future<void> renameNotebook(String id, String name) =>
      (update(notebooks)..where((t) => t.id.equals(id)))
          .write(NotebooksCompanion(name: Value(name)));

  Future<void> deleteNotebook(String id) async {
    // Cascade delete sections -> pages -> content/versions manually (FK may be off in SQLite).
    await transaction(() async {
      final secRows = await (select(sections)
            ..where((t) => t.notebookId.equals(id)))
          .get();
      for (final s in secRows) {
        await deleteSection(s.id);
      }
      await (delete(notebooks)..where((t) => t.id.equals(id))).go();
    });
  }

  // ---- Sections ----
  Future<List<Section>> sectionsFor(String notebookId) => (select(sections)
        ..where((t) => t.notebookId.equals(notebookId))
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
      .get();
  Future<void> insertSection(SectionsCompanion s) =>
      into(sections).insertOnConflictUpdate(s);

  Future<void> renameSection(String id, String name) =>
      (update(sections)..where((t) => t.id.equals(id)))
          .write(SectionsCompanion(name: Value(name)));

  Future<void> deleteSection(String id) async {
    await transaction(() async {
      final pageRows = await (select(pages)
            ..where((t) => t.sectionId.equals(id)))
          .get();
      for (final p in pageRows) {
        await deletePage(p.id);
      }
      await (delete(sections)..where((t) => t.id.equals(id))).go();
    });
  }

  // ---- Pages ----
  Future<List<Page>> pagesFor(String sectionId,
          {bool includeDeleted = false}) =>
      (select(pages)
            ..where((t) =>
                t.sectionId.equals(sectionId) &
                (includeDeleted ? const Constant(true) : t.deleted.equals(false)))
            ..orderBy([(t) => OrderingTerm.desc(t.pinned), (t) => OrderingTerm.desc(t.updatedAt)]))
          .get();
  Future<Page?> pageById(String id) =>
      (select(pages)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<Page>> trashedPages() =>
      (select(pages)..where((t) => t.deleted.equals(true))).get();

  Future<List<Page>> searchPages(String query) {
    final like = '%${query.toLowerCase()}%';
    return (select(pages)
          ..where((t) =>
              t.deleted.equals(false) & t.title.lower().like(like)))
        .get();
  }

  Future<void> insertPage(PagesCompanion p) => into(pages).insertOnConflictUpdate(p);

  Future<void> touchPage(String id) =>
      (update(pages)..where((t) => t.id.equals(id)))
          .write(PagesCompanion(updatedAt: Value(DateTime.now())));

  Future<void> togglePin(String id, bool pinned) =>
      (update(pages)..where((t) => t.id.equals(id)))
          .write(PagesCompanion(pinned: Value(pinned)));

  Future<void> softDeletePage(String id) =>
      (update(pages)..where((t) => t.id.equals(id)))
          .write(const PagesCompanion(deleted: Value(true)));

  Future<void> restorePage(String id) =>
      (update(pages)..where((t) => t.id.equals(id)))
          .write(const PagesCompanion(deleted: Value(false)));

  Future<void> deletePage(String id) async {
    await (delete(pageContent)..where((t) => t.pageId.equals(id))).go();
    await (delete(pageVersions)..where((t) => t.pageId.equals(id))).go();
    await (delete(pages)..where((t) => t.id.equals(id))).go();
  }

  // ---- Content ----
  Future<String?> contentFor(String pageId) async {
    final row = await (select(pageContent)
          ..where((t) => t.pageId.equals(pageId)))
        .getSingleOrNull();
    return row?.strokesJson;
  }

  Future<void> saveContent(String pageId, String strokesJson) =>
      into(pageContent).insertOnConflictUpdate(PageContentCompanion.insert(
        pageId: pageId,
        strokesJson: strokesJson,
        savedAt: DateTime.now(),
      ));

  // ---- Versions ----
  Future<List<PageVersion>> versionsFor(String pageId) => (select(pageVersions)
        ..where((t) => t.pageId.equals(pageId))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .get();
  Future<void> insertVersion(PageVersionsCompanion v) =>
      into(pageVersions).insert(v);

  Future<void> deleteVersion(String id) =>
      (delete(pageVersions)..where((t) => t.id.equals(id))).go();

  Future<void> pruneVersions(String pageId, int keep) async {
    final versions = await versionsFor(pageId);
    if (versions.length <= keep) return;
    for (final v in versions.skip(keep)) {
      await deleteVersion(v.id);
    }
  }

  // ---- Tags ----
  Future<List<Tag>> allTags() =>
      (select(tags)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  Future<Tag?> tagById(String id) =>
      (select(tags)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertTag(TagsCompanion t) => into(tags).insertOnConflictUpdate(t);

  Future<void> renameTag(String id, String name) =>
      (update(tags)..where((t) => t.id.equals(id)))
          .write(TagsCompanion(name: Value(name)));

  Future<void> deleteTag(String id) async {
    await (delete(pageTags)..where((t) => t.tagId.equals(id))).go();
    await (delete(tags)..where((t) => t.id.equals(id))).go();
  }

  // ---- Page-Tag junction ----
  Future<List<Tag>> tagsForPage(String pageId) async {
    final rows = await (select(pageTags)
          ..where((t) => t.pageId.equals(pageId))
          ..join([innerJoin(tags, tags.id.equalsExp(pageTags.tagId))]))
        .get();
    return rows.map((r) => r.readTable(tags)).toList();
  }

  Future<void> addTagToPage(String pageId, String tagId) =>
      into(pageTags).insertOnConflictUpdate(PageTagsCompanion.insert(
        id: _id(),
        pageId: pageId,
        tagId: tagId,
      ));

  Future<void> removeTagFromPage(String pageId, String tagId) =>
      (delete(pageTags)
            ..where((t) => t.pageId.equals(pageId) & t.tagId.equals(tagId)))
          .go();

  Future<List<NotePage>> pagesByTag(String tagId) async {
    final rows = await (select(pageTags)
          ..where((t) => t.tagId.equals(tagId))
          ..join([innerJoin(pages, pages.id.equalsExp(pageTags.pageId))]))
        .get();
    return rows.map((r) => _pageFromRow(r.readTable(pages))).toList();
  }
}
