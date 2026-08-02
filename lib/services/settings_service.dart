import 'package:shared_preferences/shared_preferences.dart';

/// Simple persistence for user preferences (theme mode, active notebook, etc.)
/// using SharedPreferences. Kept separate from the notes DB.
class SettingsService {
  SettingsService(this._prefs);

  final SharedPreferences _prefs;
  SharedPreferences get prefs => _prefs;

  static const _themeKey = 'theme_mode';
  static const _notebookKey = 'active_notebook';
  static const _sectionKey = 'active_section';
  static const _pageKey = 'active_page';
  static const _firstRunKey = 'first_run_complete';

  String get themeMode => _prefs.getString(_themeKey) ?? 'light';
  set themeMode(String v) {
    _prefs.setString(_themeKey, v);
  }

  String? get activeNotebookId => _prefs.getString(_notebookKey);
  set activeNotebookId(String? v) {
    if (v == null) {
      _prefs.remove(_notebookKey);
    } else {
      _prefs.setString(_notebookKey, v);
    }
  }

  String? get activeSectionId => _prefs.getString(_sectionKey);
  set activeSectionId(String? v) {
    if (v == null) {
      _prefs.remove(_sectionKey);
    } else {
      _prefs.setString(_sectionKey, v);
    }
  }

  String? get activePageId => _prefs.getString(_pageKey);
  set activePageId(String? v) {
    if (v == null) {
      _prefs.remove(_pageKey);
    } else {
      _prefs.setString(_pageKey, v);
    }
  }

  bool get isFirstRun => !(_prefs.getBool(_firstRunKey) ?? false);

  Future<void> markFirstRunComplete() async {
    await _prefs.setBool(_firstRunKey, true);
  }
}
