import 'dart:async';
import 'package:flutter/foundation.dart';

import '../data/repository.dart';
import '../models/stroke.dart';

/// Debounced autosave with periodic version snapshots.
///
/// Strategy (from research):
///  - Save strokes to the working DB after a 400ms debounce.
///  - Take a version snapshot every 2 minutes of inactivity, plus a manual
///    snapshot on page close.
///  - Keep the last 100 versions per page (pruned in the DB layer).
class AutosaveService extends ChangeNotifier {
  AutosaveService(this._repo);

  final NoteRepository _repo;

  NoteRepository get repo => _repo;
  Timer? _saveTimer;
  Timer? _snapshotTimer;
  String? _activePageId;
  bool _dirty = false;
  int _snapshotCount = 0;
  DateTime? _lastSavedAt;
  bool _saving = false;

  DateTime? get lastSavedAt => _lastSavedAt;
  bool get saving => _saving;

  void attach(String pageId) {
    detach();
    _activePageId = pageId;
    _snapshotCount = 0;
    _lastSavedAt = null;
    _saving = false;
    _snapshotTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_dirty) {
        _takeSnapshot(auto: true);
        _dirty = false;
      }
    });
  }

  /// Debounced save on every stroke change.
  void scheduleSave(List<Stroke> strokes) {
    if (_activePageId == null) return;
    _dirty = true;
    if (!_saving) {
      _saving = true;
      notifyListeners();
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () async {
      if (_activePageId == null) return;
      await _repo.saveStrokes(_activePageId!, strokes);
      _lastSavedAt = DateTime.now();
      _dirty = false;
      _saving = false;
      notifyListeners();
    });
  }

  /// Manual snapshot (e.g., from the version UI).
  Future<void> manualSnapshot(List<Stroke> strokes, {String label = ''}) =>
      _takeSnapshot(strokes: strokes, label: label);

  Future<void> _takeSnapshot({
    String? pageId,
    List<Stroke>? strokes,
    bool auto = false,
    String label = '',
  }) async {
    final pid = pageId ?? _activePageId;
    if (pid == null) return;
    final current = strokes ?? await _repo.strokesFor(pid);
    _snapshotCount++;
    final autoLabel = auto ? 'Auto #$_snapshotCount' : label;
    await _repo.snapshot(pid, _repo.encodeStrokes(current), label: autoLabel);
    if (auto) {
      _lastSavedAt = DateTime.now();
      notifyListeners();
    }
  }

  /// Flush pending saves + take a final snapshot. Call on page close.
  ///
  /// CORR-33: captures the page id synchronously so a subsequent [detach]
  /// (from `dispose()` in the editor) can't silently cancel the pending write.
  Future<void> flush(List<Stroke> strokes) async {
    final pageId = _activePageId;
    _saveTimer?.cancel();
    if (pageId != null && _dirty) {
      await _repo.saveStrokes(pageId, strokes);
      await _takeSnapshot(pageId: pageId, strokes: strokes, auto: true);
      _dirty = false;
    }
  }

  void detach() {
    _saveTimer?.cancel();
    _snapshotTimer?.cancel();
    _activePageId = null;
    _dirty = false;
    _saving = false;
  }
}
