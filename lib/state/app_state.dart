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

  Future<NotePage> addPage({String? title, String? sourceFilePath, String? sourceFileType}) async {
    if (_section == null) return _page!;
    final p = await _repo.createPage(
      sectionId: _section!.id,
      title: title ?? 'Untitled',
      sourceFilePath: sourceFilePath,
      sourceFileType: sourceFileType,
    );
    await _reloadTree();
    await selectPage(p.id);
    return p;
  }

  Future<void> renamePage(String id, String title) async {
    await _repo.renamePage(id, title);
    await _reloadTree();
  }

  Future<void> togglePin(String id) async {
    final target = _pages.firstWhere((p) => p.id == id);
    await _repo.togglePin(id, !target.pinned);
    await _reloadTree();
  }

  Future<void> trashPage(String id) async {
    await _repo.trashPage(id);
    await _reloadTree();
  }

  String _uuid() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}
