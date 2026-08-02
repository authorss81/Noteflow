import 'dart:async';

import '../data/repository.dart';
import '../models/stroke.dart';

/// Debounced autosave with periodic version snapshots.
///
/// Strategy (from research):
///  - Save strokes to the working DB after a 400ms debounce.
///  - Take a version snapshot every 2 minutes of inactivity, plus a manual
///    snapshot on page close.
///  - Keep the last 100 versions per page (pruned in the DB layer).
class AutosaveService {
  AutosaveService(this._repo);

  final NoteRepository _repo;

  NoteRepository get repo => _repo;
  Timer? _saveTimer;
  Timer? _snapshotTimer;
  String? _activePageId;
  bool _dirty = false;
  int _snapshotCount = 0;

  void attach(String pageId) {
    detach();
    _activePageId = pageId;
    _snapshotCount = 0;
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
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () async {
      if (_activePageId == null) return;
      await _repo.saveStrokes(_activePageId!, strokes);
      _dirty = false;
    });
  }

  /// Manual snapshot (e.g., from the version UI).
  Future<void> manualSnapshot(List<Stroke> strokes, {String label = ''}) =>
      _takeSnapshot(strokes: strokes, label: label);

  Future<void> _takeSnapshot({List<Stroke>? strokes, bool auto = false, String label = ''}) async {
    if (_activePageId == null) return;
    final current = strokes ?? await _repo.strokesFor(_activePageId!);
    _snapshotCount++;
    final autoLabel = auto ? 'Auto #$_snapshotCount' : label;
    await _repo.snapshot(_activePageId!, _repo.encodeStrokes(current), label: autoLabel);
  }

  /// Flush pending saves + take a final snapshot. Call on page close.
  Future<void> flush(List<Stroke> strokes) async {
    _saveTimer?.cancel();
    if (_activePageId != null && _dirty) {
      await _repo.saveStrokes(_activePageId!, strokes);
      await _takeSnapshot(strokes: strokes, auto: true);
      _dirty = false;
    }
  }

  void detach() {
    _saveTimer?.cancel();
    _snapshotTimer?.cancel();
    _activePageId = null;
    _dirty = false;
  }
}
