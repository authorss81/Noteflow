import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/repository.dart';
import '../models/note_models.dart';
import '../services/autosave_service.dart';
import '../services/settings_service.dart';
import '../services/encryption_service.dart';
import '../services/p2p_share_service.dart';
import '../services/plugin_loader_service.dart';
import '../services/security_service.dart';
import '../theme/app_theme.dart';

/// Central app state: theme, active notebook/section/page, and navigation.
class AppState extends ChangeNotifier {
  AppState(this._repo, this._settings) : _autosave = AutosaveService(_repo) {
    _pluginLoader = PluginLoaderService(_settings.prefs);
  }

  late final PluginLoaderService _pluginLoader;
  PluginLoaderService get pluginLoader => _pluginLoader;

  /// OS-keystore-backed security layer (R1-7). The random DEK used for E2E
  /// content encryption is persisted through this service.
  final _security = SecurityService();
  final _p2pShare = P2pShareService();

  P2pShareService get p2pShare => _p2pShare;
  String? p2pNotification;

  void clearP2pNotification() {
    p2pNotification = null;
  }

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

  /// Loads the tree + restores the last session, then starts the P2P server.
  ///
  /// Runs in the background (not awaited before `runApp`, R1-16) so the first
  /// frame renders immediately. `_loaded` flips true even on failure so the UI
  /// is never stuck on a splash.
  Future<void> bootstrap() async {
    initTheme();
    try {
      _notebook = await _repo.ensureDefaultNotebook();
      _section = await _repo.ensureDefaultSection(_notebook!.id);
      await _reloadTree(
          selectNotebook: _notebook!.id, selectSection: _section!.id);
      // Restore last session position if valid.
      final lastNb = _settings.activeNotebookId;
      final lastSec = _settings.activeSectionId;
      if (lastNb != null && _notebooks.any((n) => n.id == lastNb)) {
        await _reloadTree(selectNotebook: lastNb, selectSection: lastSec);
      }
      await _p2pShare.startServer(_onReceiveP2pNote);
    } catch (_) {
      // Keep the app usable even if the DB/P2P init fails.
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// Handles an incoming P2P note. Rejects while the vault is locked (no DEK
  /// in memory) and decrypts E2E payloads with the local DEK (R1-11). Returns
  /// whether the note was accepted.
  Future<bool> _onReceiveP2pNote(
      String title, String strokesJson, bool encrypted) async {
    if (!_authenticated) return false;
    try {
      var finalTitle = title;
      var finalJson = strokesJson;
      if (encrypted) {
        final key = _repo.encryptionKey;
        if (key == null) return false;
        // GCM auth failure here means the two devices don't share a DEK
        // (different master passwords) — reject instead of storing garbage.
        finalTitle = await EncryptionService.decrypt(title, key);
        finalJson = await EncryptionService.decrypt(strokesJson, key);
      }
      final p = await addPage(title: finalTitle);
      final strokes = _repo.decodeStrokes(finalJson);
      await _repo.saveStrokes(p.id, strokes);
      p2pNotification = "Received note '$finalTitle' from peer!";
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _p2pShare.dispose();
    super.dispose();
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

  Future<NotePage> addPage({
    String? title,
    String? sourceFilePath,
    String? sourceFileType,
    int pageIndex = 0,
    String? template,
  }) async {
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
      template: template,
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

  /// Generates a cryptographically random 16-byte salt (base64-encoded).
  static List<int> _randomSalt() {
    final rand = Random.secure();
    return List<int>.generate(16, (_) => rand.nextInt(256));
  }

  bool _authenticated = false;
  bool get authenticated => _authenticated;

  bool get hasMasterPassword => _settings.prefs.getString('master_password_salt') != null;
  bool get biometricEnabled => _settings.prefs.getBool('biometric_auth_enabled') ?? false;

  Future<bool> setMasterPassword(String password) async {
    try {
      final salt = _randomSalt();
      // KEK = Argon2id(password, salt)
      final kek = await EncryptionService.deriveKey(password, salt);
      // Random data-encryption key. All note content is encrypted with the DEK;
      // the KEK only ever wraps the DEK.
      final dek = await EncryptionService.generateDek();
      final wrappedDek = await EncryptionService.wrapDek(dek, kek);

      await _settings.prefs.setString('master_password_salt', base64Encode(salt));
      await _settings.prefs.setString('master_password_wrapped_dek', wrappedDek);

      _repo.encryptionKey = dek;
      _authenticated = true;
      await _maybeMigrateLegacyData();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyMasterPassword(String password) async {
    try {
      final saltString = _settings.prefs.getString('master_password_salt');
      final wrappedDek = _settings.prefs.getString('master_password_wrapped_dek');
      if (saltString == null || wrappedDek == null) return false;

      final salt = base64Decode(saltString);
      final kek = await EncryptionService.deriveKey(password, salt);
      // Wrong password => GCM auth tag fails => throws => returns false.
      final dek = await EncryptionService.unwrapDek(wrappedDek, kek);

      _repo.encryptionKey = dek;
      _authenticated = true;
      await _maybeMigrateLegacyData();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setBiometricEnabled(bool enabled, String masterPassword) async {
    try {
      final verify = await verifyMasterPassword(masterPassword);
      if (!verify || _repo.encryptionKey == null) return false;

      if (enabled) {
        // Store only the random DEK (not the human-readable master password)
        // in the OS keystore/keychain via SecurityService (R1-7).
        await _security.storeDek(_repo.encryptionKey!);
        await _settings.prefs.setBool('biometric_auth_enabled', true);
      } else {
        await _security.clearDek();
        await _settings.prefs.setBool('biometric_auth_enabled', false);
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyBiometricsAndUnlock() async {
    if (!biometricEnabled) return false;
    try {
      final dek = await _security.readDek();
      if (dek == null) return false;
      _repo.encryptionKey = dek;
      _authenticated = true;
      await _maybeMigrateLegacyData();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> removeMasterPassword() async {
    await _settings.prefs.remove('master_password_salt');
    await _settings.prefs.remove('master_password_wrapped_dek');
    await _settings.prefs.remove('biometric_auth_enabled');
    await _security.clearDek();
    _repo.encryptionKey = null;
    _authenticated = false;
    notifyListeners();
  }

  /// One-time migration: rewrites any legacy plaintext metadata to encrypted
  /// form after the first successful unlock with a master password (R1-10).
  Future<void> _maybeMigrateLegacyData() async {
    if (_settings.prefs.getBool('metadata_encryption_v1') != true) {
      await _repo.migrateLegacyMetadata();
      await _settings.prefs.setBool('metadata_encryption_v1', true);
    }
  }

  void lock() {
    _inactivityTimer?.cancel();
    _repo.encryptionKey = null;
    _authenticated = false;
    notifyListeners();
  }

  Timer? _inactivityTimer;
  static const _inactivityTimeout = Duration(minutes: 5);

  /// Auto-lock when the app is backgrounded (paused/hidden/detached): the DEK
  /// is dropped from memory immediately so the vault re-locks on return
  /// (R1-9).
  void onBackgrounded() {
    _inactivityTimer?.cancel();
    if (hasMasterPassword && _authenticated) {
      lock();
    }
  }

  /// On resume the vault may still be unlocked if it was never backgrounded
  /// (e.g. quick app-switch that didn't pause) — re-arm the inactivity timer.
  void onResumed() {
    if (!hasMasterPassword) return;
    if (_authenticated) {
      _armInactivityTimer();
    }
  }

  /// Registers user activity (pointer/touch events) to reset the inactivity
  /// timer. Wired from the root widget's [Listener].
  void registerActivity() {
    if (!hasMasterPassword || !_authenticated) return;
    _armInactivityTimer();
  }

  void _armInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, () {
      if (hasMasterPassword && _authenticated) {
        lock();
      }
    });
  }
}
