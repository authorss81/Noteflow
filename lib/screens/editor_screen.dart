import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

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
  final _boundaryKey = GlobalKey();
  late final ImportService _import;

  StrokeTool _tool = StrokeTool.pen;
  Color _color = const Color(0xFF1B365D); // ink-blue default
  double _width = 3;

  late NotePage _page;
  List<Stroke> _strokes = [];
  ui.Image? _background;
  bool _loadingBg = false;
  bool _previewMarkdown = false;
  AppLifecycleListener? _lifecycle;

  // Multi-page PDF support (R1-22): the page count and the current page's
  // annotation slice (strokes are stamped with their PDF page).
  int _pdfPageCount = 0;
  List<Stroke> _pageStrokes = [];
  bool get _isPdf => _page.sourceFileType == 'pdf';

  @override
  void initState() {
    super.initState();
    _import = ImportService(
        keyProvider: () => widget.autosave.repo.encryptionKey);
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
    final type = _page.sourceFileType;
    final oldBg = _background;
    _background = null;
    _pageStrokes = _isPdf
        ? _strokes.where((s) => s.page == _page.pageIndex).toList()
        : _strokes;
    if (src != null) {
      if (type == 'pdf') {
        final count = await _import.pdfPageCount(src);
        if (!mounted) return;
        setState(() => _pdfPageCount = count);
      } else {
        _pdfPageCount = 0;
      }
      final f = await _import.loadBackground(
          src, type ?? 'image', pageIndex: _page.pageIndex);
      oldBg?.dispose();
      if (mounted) setState(() => _background = f);
    } else {
      oldBg?.dispose();
      _pdfPageCount = 0;
    }
    if (mounted) setState(() => _loadingBg = false);
    widget.autosave.attach(_page.id);
  }

  /// Flips a multi-page PDF to another page: persists the new [NotePage]
  /// pageIndex so it resumes there, reloads the background, and swaps the
  /// canvas to that page's annotations (R1-22).
  Future<void> _goToPdfPage(int index) async {
    if (!_isPdf || index < 0 || index >= _pdfPageCount) return;
    if (index == _page.pageIndex) return;
    setState(() => _loadingBg = true);
    _page = _page.copyWith(pageIndex: index);
    await widget.autosave.repo.setPageIndex(_page.id, index);
    final oldBg = _background;
    _background = null;
    _pageStrokes = _strokes.where((s) => s.page == index).toList();
    final src = _page.sourceFilePath;
    if (src != null) {
      final f = await _import.loadBackground(
          src, _page.sourceFileType ?? 'image', pageIndex: index);
      oldBg?.dispose();
      if (mounted) setState(() => _background = f);
    } else {
      oldBg?.dispose();
    }
    if (mounted) setState(() => _loadingBg = false);
  }

  void _showPdfStrip() {
    final src = _page.sourceFilePath;
    if (src == null) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _PdfPageStrip(
        import: _import,
        path: src,
        count: _pdfPageCount,
        current: _page.pageIndex,
        onSelect: (i) async {
          Navigator.pop(ctx);
          await _goToPdfPage(i);
        },
      ),
    );
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
    if (_isPdf) {
      // The canvas only edits the current PDF page's slice; re-merge it into
      // the full per-page list before persisting (R1-22).
      final others = _strokes.where((x) => x.page != _page.pageIndex).toList();
      _strokes = [...others, ...s];
      _pageStrokes = s;
    } else {
      _strokes = s;
      _pageStrokes = s;
    }
    widget.autosave.scheduleSave(_strokes);
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

  Future<Uint8List?> _capturePngBytes() async {
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _sharePng() async {
    final bytes = await _capturePngBytes();
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate PNG image')),
        );
      }
      return;
    }
    final tempDir = await getTemporaryDirectory();
    final file = io.File('${tempDir.path}/${_page.title}.png');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Exported Page: ${_page.title}',
      ),
    );
  }

  Future<void> _sharePdf() async {
    final bytes = await _capturePngBytes();
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate PDF document')),
        );
      }
      return;
    }
    final pdf = pw.Document();
    final image = pw.MemoryImage(bytes);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(10),
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          );
        },
      ),
    );

    final tempDir = await getTemporaryDirectory();
    final file = io.File('${tempDir.path}/${_page.title}.pdf');
    await file.writeAsBytes(await pdf.save());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Exported Page: ${_page.title}',
      ),
    );
  }

  String _compileMarkdown() {
    final textStrokes = _strokes
        .where((s) => s.tool == StrokeTool.text && s.text.trim().isNotEmpty)
        .toList();
    // Sort top-to-bottom, then left-to-right
    textStrokes.sort((a, b) {
      final ay = a.start?.dy ?? (a.points.isNotEmpty ? a.points.first.dy : 0.0);
      final by = b.start?.dy ?? (b.points.isNotEmpty ? b.points.first.dy : 0.0);
      if ((ay - by).abs() > 20) {
        return ay.compareTo(by);
      }
      final ax = a.start?.dx ?? (a.points.isNotEmpty ? a.points.first.dx : 0.0);
      final bx = b.start?.dx ?? (b.points.isNotEmpty ? b.points.first.dx : 0.0);
      return ax.compareTo(bx);
    });

    if (textStrokes.isEmpty) {
      return '*No text annotations on this page. Add some text elements to see them rendered in Markdown.*';
    }

    return textStrokes.map((s) => s.text).join('\n\n');
  }

String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<Color?> _pickColorDialog(BuildContext context, Color initial) {
    Color picked = initial;
    return showDialog<Color>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Pick color'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final c in _EditorBody._colors)
                      Material(
                        color: c,
                        shape: const CircleBorder(),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(ctx, c),
                          child: const SizedBox(width: 32, height: 32),
                        ),
                      ),
                    Material(
                      color: picked,
                      shape: const CircleBorder(),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.pop(ctx, picked),
                        child: const SizedBox(width: 32, height: 32),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: picked.r / 255,
                        min: 0,
                        max: 1,
                        onChanged: (v) {
                          picked = Color.fromRGBO(
                            (v * 255).round(),
                            picked.g.round().clamp(0, 255),
                            picked.b.round().clamp(0, 255),
                            picked.a,
                          );
                          setDialogState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: picked.g / 255,
                        min: 0,
                        max: 1,
                        onChanged: (v) {
                          picked = Color.fromRGBO(
                            picked.r.round().clamp(0, 255),
                            (v * 255).round(),
                            picked.b.round().clamp(0, 255),
                            picked.a,
                          );
                          setDialogState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: picked.b / 255,
                        min: 0,
                        max: 1,
                        onChanged: (v) {
                          picked = Color.fromRGBO(
                            picked.r.round().clamp(0, 255),
                            picked.g.round().clamp(0, 255),
                            (v * 255).round(),
                            picked.a,
                          );
                          setDialogState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, picked),
              child: const Text('Select'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
appBar: AppBar(
        automaticallyImplyLeading: false,
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
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
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
          IconButton(
            tooltip: 'Pick color',
            icon: Icon(Icons.color_lens, color: _color),
            onPressed: () async {
              final picked = await _pickColorDialog(context, _color);
              if (picked != null && mounted) {
                setState(() => _color = picked);
              }
            },
          ),
          IconButton(
            tooltip: 'Stroke width',
            icon: Icon(Icons.circle, size: _width.clamp(2, 24).toDouble()),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                builder: (_) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Stroke width',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Slider(
                        value: _width,
                        min: 1,
                        max: 24,
                        divisions: 23,
                        onChanged: (w) => setState(() => _width = w),
                        label: '${_width.round()}px',
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: _previewMarkdown ? 'Edit canvas' : 'Preview markdown',
            icon: Icon(_previewMarkdown ? Icons.edit : Icons.menu_book),
            onPressed: () => setState(() => _previewMarkdown = !_previewMarkdown),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.share),
            tooltip: 'Export & Share',
            onSelected: (val) {
              if (val == 'png') {
                _sharePng();
              } else if (val == 'pdf') {
                _sharePdf();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'png', child: Text('Share as PNG image')),
              const PopupMenuItem(value: 'pdf', child: Text('Share as PDF document')),
            ],
          ),
          _EditorThemeMenu(),
          PopupMenuButton<StrokeTool>(
            onSelected: (t) => setState(() => _tool = t),
            itemBuilder: (_) => StrokeTool.values
                .map((t) => PopupMenuItem(value: t, child: Text(t.label)))
                .toList(),
          ),
        ],
        bottom: _isPdf && _pdfPageCount > 1
          ? PreferredSize(
              preferredSize: const Size.fromHeight(44),
              child: _PdfPager(
                current: _page.pageIndex,
                count: _pdfPageCount,
                onPrev: () => _goToPdfPage(_page.pageIndex - 1),
                onNext: () => _goToPdfPage(_page.pageIndex + 1),
                onShowAll: _showPdfStrip,
              ),
            )
          : null,
      ),
      body: _loadingBg
          ? const Center(child: CircularProgressIndicator())
          : _previewMarkdown
              ? Container(
                  color: Theme.of(context).colorScheme.surface,
                  width: double.infinity,
                  height: double.infinity,
                  padding: const EdgeInsets.all(24),
                  child: SingleChildScrollView(
                    child: MarkdownBody(
                      data: _compileMarkdown(),
                      selectable: true,
                    ),
                  ),
                )
              : _EditorBody(
                  canvasKey: _canvasKey,
              boundaryKey: _boundaryKey,
              tool: _tool,
              color: _color,
              width: _width,
              strokes: _isPdf ? _pageStrokes : _strokes,
              canvasPage: _isPdf ? _page.pageIndex : 0,
              background: _background,
              template: _page.template,
              onChanged: _onStrokesChanged,
              onTool: (t) => setState(() => _tool = t),
              onColor: (c) => setState(() => _color = c),
              onWidth: (w) => setState(() => _width = w),
            ),
    );
  }

  void _showVersions() async {
    final versions = await widget.autosave.repo.decryptedVersions(_page.id);
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
          if (_isPdf) {
            // The restored snapshot covers all PDF pages; show only the
            // current page's slice on the canvas (R1-22).
            _pageStrokes = s.where((x) => x.page == _page.pageIndex).toList();
            _canvasKey.currentState?.setStrokes(_pageStrokes);
          } else {
            _pageStrokes = s;
            _canvasKey.currentState?.setStrokes(s);
          }
          widget.autosave.scheduleSave(_strokes);
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
    required this.boundaryKey,
    required this.tool,
    required this.color,
    required this.width,
    required this.strokes,
    this.canvasPage = 0,
    required this.background,
    this.template,
    required this.onChanged,
    required this.onTool,
    required this.onColor,
    required this.onWidth,
  });

  final GlobalKey<AnnotationCanvasState> canvasKey;
  final GlobalKey boundaryKey;
  final StrokeTool tool;
  final Color color;
  final double width;
  final List<Stroke> strokes;
  final int canvasPage;
  final ui.Image? background;
  final String? template;
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
          child: RepaintBoundary(
            key: boundaryKey,
            child: AnnotationCanvas(
              key: canvasKey,
              tool: tool,
              color: color,
              width: width,
              initialStrokes: strokes,
              backgroundImage: background,
              template: template,
              onChanged: onChanged,
              page: canvasPage,
            ),
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
              _toolBtn(context, StrokeTool.select, Icons.pan_tool, 'Pan/Zoom'),
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

  bool _sameStrokes(List<Stroke> a, List<Stroke> b) {
    if (identical(a, b)) return true;
    return widget.autosave.repo.encodeStrokes(a) ==
        widget.autosave.repo.encodeStrokes(b);
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
                      // CORR-34: List<Stroke> == compares by identity, so the
                      // highlight never matched. Compare normalized JSON instead.
                      selected: _sameStrokes(_preview, widget.current),
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

/// Compact prev/next page bar shown under the AppBar for multi-page PDFs
/// (R1-22).
class _PdfPager extends StatelessWidget {
  const _PdfPager({
    required this.current,
    required this.count,
    required this.onPrev,
    required this.onNext,
    required this.onShowAll,
  });

  final int current;
  final int count;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous page',
            icon: const Icon(Icons.chevron_left),
            onPressed: current > 0 ? onPrev : null,
          ),
          Text('${current + 1} / $count'),
          IconButton(
            tooltip: 'Next page',
            icon: const Icon(Icons.chevron_right),
            onPressed: current < count - 1 ? onNext : null,
          ),
          const Spacer(),
          IconButton(
            tooltip: 'All pages',
            icon: const Icon(Icons.grid_view),
            onPressed: onShowAll,
          ),
        ],
      ),
    );
  }
}

/// Horizontal thumbnail strip of all PDF pages (R1-22). Opens the document
/// once (avoiding N decryptions) and renders thumbnails lazily as they scroll
/// into view; the whole strip is disposed when the sheet closes.
class _PdfPageStrip extends StatefulWidget {
  const _PdfPageStrip({
    required this.import,
    required this.path,
    required this.count,
    required this.current,
    required this.onSelect,
  });

  final ImportService import;
  final String path;
  final int count;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  State<_PdfPageStrip> createState() => _PdfPageStripState();
}

class _PdfPageStripState extends State<_PdfPageStrip> {
  PdfDocument? _doc;
  final Map<int, ui.Image> _images = {};
  final Set<int> _loading = {};

  @override
  void initState() {
    super.initState();
    widget.import.openPdf(widget.path).then((doc) {
      if (!mounted) {
        doc?.dispose();
        return;
      }
      setState(() => _doc = doc);
    });
  }

  @override
  void dispose() {
    _doc?.dispose();
    for (final img in _images.values) {
      img.dispose();
    }
    super.dispose();
  }

  void _ensure(int index) {
    final doc = _doc;
    if (doc == null || _images.containsKey(index) || _loading.contains(index)) {
      return;
    }
    _loading.add(index);
    widget.import.renderPdfThumbnailFrom(doc, index).then((img) {
      if (!mounted) return;
      if (img != null) _images[index] = img;
      _loading.remove(index);
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SizedBox(
        height: 190,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text('Pages (${widget.count})',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: widget.count,
                itemBuilder: (context, i) {
                  _ensure(i);
                  final img = _images[i];
                  final isCurrent = i == widget.current;
                  return GestureDetector(
                    onTap: () => widget.onSelect(i),
                    child: Container(
                      width: 88,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        border: Border.all(
                          width: 2,
                          color:
                              isCurrent ? scheme.primary : scheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: img == null
                                ? const Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : Padding(
                                    padding: const EdgeInsets.all(3),
                                    child: RawImage(
                                        image: img, fit: BoxFit.contain),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(2),
                            child: Text('${i + 1}',
                                style: const TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

