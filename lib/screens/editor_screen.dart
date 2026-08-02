import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../models/note_models.dart';
import '../models/stroke.dart';
import '../services/autosave_service.dart';
import '../services/import_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/annotation_canvas.dart';

/// The annotation editor: page canvas + toolbar + version history.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.page, required this.autosave});

  final NotePage page;
  final AutosaveService autosave;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _canvasKey = GlobalKey<AnnotationCanvasState>();
  final ImportService _import = ImportService();

  StrokeTool _tool = StrokeTool.pen;
  Color _color = const Color(0xFF1B365D); // ink-blue default
  double _width = 3;

  late NotePage _page;
  List<Stroke> _strokes = [];
  ui.Image? _background;
  bool _loadingBg = false;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _page = widget.page;
    _loadPage();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) {
          widget.autosave.flush(_strokes);
        }
      },
    );
  }

  @override
  void didUpdateWidget(EditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.id != widget.page.id) {
      _page = widget.page;
      _loadPage();
    } else if (oldWidget.page.title != widget.page.title) {
      _page = _page.copyWith(title: widget.page.title);
    }
  }

  Future<void> _loadPage() async {
    if (!mounted) return;
    setState(() => _loadingBg = true);
    final strokes = await widget.autosave.repo.strokesFor(_page.id);
    if (!mounted) return;
    _strokes = strokes;

    final src = _page.sourceFilePath;
    if (src != null) {
      final f = await _import.loadBackground(src, _page.sourceFileType ?? 'image');
      if (mounted) setState(() => _background = f);
    }
    if (mounted) setState(() => _loadingBg = false);
    widget.autosave.attach(_page.id);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    widget.autosave.flush(_strokes);
    widget.autosave.detach();
    _background?.dispose();
    super.dispose();
  }

  void _onStrokesChanged(List<Stroke> s) {
    _strokes = s;
    widget.autosave.scheduleSave(s);
  }

  void _renamePage() {
    final controller = TextEditingController(text: _page.title);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename page'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                context.read<AppState>().renamePage(_page.id, name);
                setState(() {
                  _page = _page.copyWith(title: name);
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _renamePage,
              child: Text(_page.title,
                  style: const TextStyle(fontSize: 18)),
            ),
            ListenableBuilder(
              listenable: widget.autosave,
              builder: (context, _) {
                final saving = widget.autosave.saving;
                final lastSavedAt = widget.autosave.lastSavedAt;
                return Text(
                  _loadingBg
                      ? 'Loading…'
                      : (saving
                          ? 'Saving…'
                          : lastSavedAt != null
                              ? 'Saved ${_formatTime(lastSavedAt)}'
                              : 'Autosaved'),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                );
              },
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
            onPressed: () => _canvasKey.currentState?.undo(),
          ),
          IconButton(
            tooltip: 'Redo',
            icon: const Icon(Icons.redo),
            onPressed: () => _canvasKey.currentState?.redo(),
          ),
          IconButton(
            tooltip: 'Zoom in',
            icon: const Icon(Icons.zoom_in),
            onPressed: () => _canvasKey.currentState?.zoomIn(),
          ),
          IconButton(
            tooltip: 'Zoom out',
            icon: const Icon(Icons.zoom_out),
            onPressed: () => _canvasKey.currentState?.zoomOut(),
          ),
          IconButton(
            tooltip: 'Fit page',
            icon: const Icon(Icons.fit_screen),
            onPressed: () => _canvasKey.currentState?.fit(),
          ),
          IconButton(
            tooltip: 'Version history',
            icon: const Icon(Icons.history),
            onPressed: _showVersions,
          ),
          _EditorThemeMenu(),
          PopupMenuButton<StrokeTool>(
            onSelected: (t) => setState(() => _tool = t),
            itemBuilder: (_) => StrokeTool.values
                .map((t) => PopupMenuItem(value: t, child: Text(t.label)))
                .toList(),
          ),
        ],
      ),
      body: _loadingBg
          ? const Center(child: CircularProgressIndicator())
          : _EditorBody(
              canvasKey: _canvasKey,
              tool: _tool,
              color: _color,
              width: _width,
              strokes: _strokes,
              background: _background,
              onChanged: _onStrokesChanged,
              onTool: (t) => setState(() => _tool = t),
              onColor: (c) => setState(() => _color = c),
              onWidth: (w) => setState(() => _width = w),
            ),
    );
  }

  void _showVersions() async {
    final versions = await widget.autosave.repo.versions(_page.id);
    if (!mounted) return;
    if (versions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No version history yet. Make some edits first.')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _VersionsSheet(
        versions: versions,
        current: _strokes,
        autosave: widget.autosave,
        onRestore: (s) async {
          if (!mounted) return;
          // Preserve the current state before overwriting it with the restore.
          await widget.autosave.manualSnapshot(_strokes, label: 'Before restore');
          if (!mounted) return;
          _strokes = s;
          _canvasKey.currentState?.setStrokes(s);
          widget.autosave.scheduleSave(s);
        },
      ),
    );
  }
}

// ---------- Theme menu (also available inside the editor) ----------
class _EditorThemeMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return PopupMenuButton<AppThemeMode>(
      icon: const Icon(Icons.palette_outlined),
      tooltip: 'Theme',
      onSelected: app.setTheme,
      itemBuilder: (_) => [
        for (final m in AppThemeMode.values)
          PopupMenuItem(
            value: m,
            child: Row(
              children: [
                Icon(
                  m == app.theme ? Icons.check : Icons.circle_outlined,
                  size: 16,
                  color: PaperPalette.of(m).accent,
                ),
                const SizedBox(width: 8),
                Text(_label(m)),
              ],
            ),
          ),
      ],
    );
  }

  String _label(AppThemeMode m) => switch (m) {
        AppThemeMode.light => 'Light (paper)',
        AppThemeMode.sepia => 'Sepia',
        AppThemeMode.dark => 'Dark',
        AppThemeMode.amoled => 'AMOLED black',
      };
}

class _EditorBody extends StatelessWidget {
  const _EditorBody({
    required this.canvasKey,
    required this.tool,
    required this.color,
    required this.width,
    required this.strokes,
    required this.background,
    required this.onChanged,
    required this.onTool,
    required this.onColor,
    required this.onWidth,
  });

  final GlobalKey<AnnotationCanvasState> canvasKey;
  final StrokeTool tool;
  final Color color;
  final double width;
  final List<Stroke> strokes;
  final ui.Image? background;
  final ValueChanged<List<Stroke>> onChanged;
  final ValueChanged<StrokeTool> onTool;
  final ValueChanged<Color> onColor;
  final ValueChanged<double> onWidth;

  static const _colors = [
    Color(0xFF1B365D), // ink blue
    Color(0xFF512906), // sepia brown
    Color(0xFFB3261E), // red
    Color(0xFF006B3F), // green
    Color(0xFF7A1FA2), // purple
    Color(0xFF000000), // black
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Toolbar(
          tool: tool,
          color: color,
          width: width,
          onTool: onTool,
          onColor: onColor,
          onWidth: onWidth,
        ),
        Expanded(
          child: AnnotationCanvas(
            key: canvasKey,
            tool: tool,
            color: color,
            width: width,
            initialStrokes: strokes,
            backgroundImage: background,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.tool,
    required this.color,
    required this.width,
    required this.onTool,
    required this.onColor,
    required this.onWidth,
  });

  final StrokeTool tool;
  final Color color;
  final double width;
  final ValueChanged<StrokeTool> onTool;
  final ValueChanged<Color> onColor;
  final ValueChanged<double> onWidth;

  Widget _toolBtn(BuildContext context, StrokeTool t, IconData icon, String label) {
    final selected = tool == t;
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onTool(t),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _toolBtn(context, StrokeTool.pen, Icons.draw, 'Pen'),
              _toolBtn(context, StrokeTool.highlighter, Icons.border_color, 'Highlighter'),
              _toolBtn(context, StrokeTool.eraser, Icons.cleaning_services_outlined, 'Eraser'),
              _toolBtn(context, StrokeTool.text, Icons.text_fields, 'Text'),
              _toolBtn(context, StrokeTool.rect, Icons.crop_square, 'Rectangle'),
              _toolBtn(context, StrokeTool.line, Icons.horizontal_rule, 'Line'),
              _toolBtn(context, StrokeTool.arrow, Icons.arrow_outward, 'Arrow'),
              _toolBtn(context, StrokeTool.ellipse, Icons.circle_outlined, 'Ellipse'),
              const SizedBox(width: 8),
              Container(width: 1, height: 24, color: scheme.outlineVariant),
              const SizedBox(width: 8),
              ..._EditorBody._colors.map((c) => InkWell(
                    onTap: () => onColor(c),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == color ? scheme.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  )),
              const SizedBox(width: 12),
              Icon(Icons.line_weight, size: 18, color: scheme.onSurfaceVariant),
              Slider(
                value: width,
                min: 1,
                max: 12,
                onChanged: onWidth,
                semanticFormatterCallback: (v) => '${v.round()}px',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionsSheet extends StatefulWidget {
  const _VersionsSheet({
    required this.versions,
    required this.current,
    required this.autosave,
    required this.onRestore,
  });

  final List<PageVersion> versions;
  final List<Stroke> current;
  final AutosaveService autosave;
  final ValueChanged<List<Stroke>> onRestore;

  @override
  State<_VersionsSheet> createState() => _VersionsSheetState();
}

class _VersionsSheetState extends State<_VersionsSheet> {
  List<Stroke> _preview = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final first = widget.versions.first;
    _preview = widget.autosave.repo.decodeStrokes(first.strokesJson);
    setState(() {});
  }

  Future<bool?> _confirmRestore(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore this version?'),
        content: const Text(
            'Your current strokes will be saved as a backup version first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Version History',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: widget.versions.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return ListTile(
                      leading: const Icon(Icons.edit_note),
                      title: const Text('Current version'),
                      trailing: const Text('now',
                          style: TextStyle(color: Colors.grey)),
                      selected: _preview == widget.current,
                    );
                  }
                  final v = widget.versions[i - 1];
                  return ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(v.label.isEmpty ? 'Snapshot' : v.label),
                    subtitle: Text('${v.createdAt.toLocal()}'),
                    trailing: FilledButton.tonal(
                      onPressed: () async {
                        final confirmed = await _confirmRestore(context);
                        if (confirmed != true) return;
                        if (!context.mounted) return;
                        final s =
                            widget.autosave.repo.decodeStrokes(v.strokesJson);
                        widget.onRestore(s);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Restored version')),
                        );
                      },
                      child: const Text('Restore'),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

