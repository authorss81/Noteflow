import 'package:flutter/foundation.dart';

import '../data/repository.dart';
import '../models/note_models.dart';
import '../services/autosave_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Central app state: theme, active notebook/section/page, and navigation.
class AppState extends ChangeNotifier {
  AppState(this._repo, this._settings) : _autosave = AutosaveService(_repo);

  final NoteRepository _repo;
  final SettingsService _settings;

  final AutosaveService _autosave;
  AutosaveService get autosave => _autosave;
  NoteRepository get repo => _repo;
  SettingsService get settings => _settings;

  AppThemeMode _theme = AppThemeMode.light;
  AppThemeMode get theme => _theme;

  List<Notebook> _notebooks = [];
  List<Section> _sections = [];
  List<NotePage> _pages = [];

  Notebook? _notebook;
  Section? _section;
  NotePage? _page;

  bool _loaded = false;
  bool get loaded => _loaded;

  List<Notebook> get notebooks => _notebooks;
  List<Section> get sections => _sections;
  List<NotePage> get pages => _pages;
  Notebook? get notebook => _notebook;
  Section? get section => _section;
  NotePage? get page => _page;

  List<NotePage> _trashed = [];
  List<NotePage> _recent = [];
  List<NotePage> get trashed => _trashed;
  List<NotePage> get recent => _recent;

  Future<void> loadTrash() async {
    _trashed = await _repo.trashedPages();
    notifyListeners();
  }

  Future<List<NotePage>> searchPages(String query) async =>
      _repo.searchPages(query);

  Future<void> loadRecent() async {
    final all = <NotePage>[];
    for (final nb in _notebooks) {
      for (final s in await _repo.sections(nb.id)) {
        all.addAll(await _repo.pages(s.id));
      }
    }
    all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _recent = all.take(20).toList();
    notifyListeners();
  }

  void initTheme() {
    _theme = AppThemeMode.values.firstWhere(
      (m) => m.name == _settings.themeMode,
      orElse: () => AppThemeMode.light,
    );
  }

  void setTheme(AppThemeMode mode) {
    if (_theme == mode) return;
    _theme = mode;
    _settings.themeMode = mode.name;
    notifyListeners();
  }

  Future<void> bootstrap() async {
    initTheme();
    _notebook = await _repo.ensureDefaultNotebook();
    _section = await _repo.ensureDefaultSection(_notebook!.id);
    await _reloadTree(selectNotebook: _notebook!.id, selectSection: _section!.id);
    // Restore last session position if valid.
    final lastNb = _settings.activeNotebookId;
    final lastSec = _settings.activeSectionId;
    if (lastNb != null && _notebooks.any((n) => n.id == lastNb)) {
      await _reloadTree(selectNotebook: lastNb, selectSection: lastSec);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _reloadTree({
    String? selectNotebook,
    String? selectSection,
  }) async {
    _notebooks = await _repo.notebooks();
    if (selectNotebook != null) {
      _notebook = _findOrFirst(_notebooks, selectNotebook);
    } else {
      _notebook = _notebooks.isNotEmpty ? _notebooks.first : null;
    }
    if (_notebook == null) {
      _sections = [];
      _pages = [];
      _section = null;
      _page = null;
      return;
    }
    _sections = await _repo.sections(_notebook!.id);
    if (selectSection != null) {
      _section = _findOrFirst(_sections, selectSection);
    } else if (_section == null || _section!.notebookId != _notebook!.id) {
      _section = _sections.isNotEmpty ? _sections.first : null;
    }
    if (_section != null) {
      _pages = await _repo.pages(_section!.id);
    } else {
      _pages = [];
    }
    notifyListeners();
  }

  static T? _findOrFirst<T>(List<T> list, String id) {
    for (final item in list) {
      if (item is Notebook && item.id == id) return item;
      if (item is Section && item.id == id) return item;
    }
    return list.isNotEmpty ? list.first : null;
  }

  Future<void> selectNotebook(String id) async {
    await _reloadTree(selectNotebook: id);
    _settings.activeNotebookId = id;
  }

  Future<void> selectSection(String id) async {
    await _reloadTree(selectSection: id);
    _settings.activeSectionId = id;
  }

  Future<void> selectPage(String id) async {
    _page = await _repo.page(id);
    _settings.activePageId = id;
    notifyListeners();
  }

  Future<Notebook> addNotebook(String name) async {
    final n = Notebook(id: _uuid(), name: name.trim(), createdAt: DateTime.now());
    await _repo.insertNotebook(n);
    await _repo.insertSection(Section(
        id: _uuid(), notebookId: n.id, name: 'Quick Notes', createdAt: DateTime.now()));
    await _reloadTree(selectNotebook: n.id);
    return n;
  }

  Future<void> addSection(String name) async {
    if (_notebook == null) return;
    await _repo.insertSection(
        Section(id: _uuid(), notebookId: _notebook!.id, name: name.trim(), createdAt: DateTime.now()));
    await _reloadTree();
  }

  Future<NotePage> addPage({String? title, String? sourceFilePath, String? sourceFileType, int pageIndex = 0}) async {
    final section = _section ?? (_sections.isNotEmpty ? _sections.first : null);
    if (section == null) {
      throw StateError('No section selected');
    }
    final p = await _repo.createPage(
      sectionId: section.id,
      title: title ?? 'Untitled',
      sourceFilePath: sourceFilePath,
      sourceFileType: sourceFileType,
      pageIndex: pageIndex,
    );
    await _reloadTree();
    await selectPage(p.id);
    return p;
  }

  Future<void> renamePage(String id, String title) async {
    await _repo.renamePage(id, title);
    if (_page?.id == id) _page = await _repo.page(id);
    await _reloadTree();
  }

  Future<void> togglePin(String id) async {
    final target = _pages.where((p) => p.id == id).firstOrNull;
    if (target == null) return;
    await _repo.togglePin(id, !target.pinned);
    await _reloadTree();
  }

  Future<void> trashPage(String id) async {
    await _repo.trashPage(id);
    await _reloadTree();
  }

  Future<void> restorePage(String id) async {
    await _repo.restorePage(id);
    await _reloadTree();
  }

  Future<void> deletePage(String id) async {
    final p = await _repo.page(id);
    await _repo.deletePage(id, sourceFilePath: p?.sourceFilePath);
    await _reloadTree();
  }

  Future<void> emptyTrash() async {
    await _repo.emptyTrash();
    await _reloadTree();
  }

  Future<void> renameNotebook(String id, String name) async {
    await _repo.renameNotebook(id, name);
    await _reloadTree();
  }

  Future<void> deleteNotebook(String id) async {
    final wasActive = _notebook?.id == id;
    await _repo.deleteNotebook(id);
    if (wasActive) {
      _notebook = null;
      _section = null;
      _page = null;
      await _reloadTree();
    } else {
      await _reloadTree();
    }
  }

  Future<void> renameSection(String id, String name) async {
    await _repo.renameSection(id, name);
    await _reloadTree();
  }

  Future<void> deleteSection(String id) async {
    final wasActive = _section?.id == id;
    await _repo.deleteSection(id);
    if (wasActive) {
      _section = null;
      _page = null;
      await _reloadTree();
    } else {
      await _reloadTree();
    }
  }

  String _uuid() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}
