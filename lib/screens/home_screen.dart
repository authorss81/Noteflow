import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:archive/archive_io.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note_models.dart';
import '../models/stroke.dart';
import '../services/import_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'editor_screen.dart';
import 'markdown_preview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkWelcome());
  }

  Future<void> _checkWelcome() async {
    if (!mounted) return;
    final app = context.read<AppState>();
    if (app.settings.isFirstRun) {
      _showWelcome(app);
    }
  }

  void _showWelcome(AppState app) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: scheme.surface,
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.draw_outlined, size: 40, color: scheme.primary),
            ),
            const SizedBox(height: 16),
            const Text(
              'Welcome to Noteflow',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Offline-first, privacy-focused canvas & PDF annotation.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
              ),
              const SizedBox(height: 24),
              _welcomeFeatureRow(
                context,
                Icons.security_outlined,
                '100% Private',
                'Your notes stay on your device. No cloud sync, no tracking.',
              ),
              const SizedBox(height: 16),
              _welcomeFeatureRow(
                context,
                Icons.picture_as_pdf_outlined,
                'PDF & Document Annotation',
                'Import PDFs, images, or text documents to sketch and write directly on them.',
              ),
              const SizedBox(height: 16),
              _welcomeFeatureRow(
                context,
                Icons.save_outlined,
                'Autosave & History',
                'Every stroke is saved instantly. Roll back to any point with detailed version snapshots.',
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              await app.settings.markFirstRunComplete();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Get Started', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _welcomeFeatureRow(BuildContext context, IconData icon, String title, String subtitle) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: scheme.primary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }

  String _strokeId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  Future<void> _importFiles(BuildContext context, AppState app) async {
    final import = ImportService();
    final files = await import.pickFiles();
    if (files.isEmpty) return;
    NotePage? lastPage;
    int importedCount = 0;
    for (final f in files) {
      final ext = import.extensionOf(f.name);
      final type = import.isPdf(ext) ? 'pdf' : import.isImage(ext) ? 'image' : 'text';
      final path = await import.persistFile(f.name, f.bytes);
      if (type == 'pdf') {
        // Multipage PDF: render all pages, create a NotePage per page.
        final pages = await import.loadPdfPages(path);
        if (pages.isEmpty) {
          // Fallback: create a single page with no background.
          final page = await app.addPage(
            title: f.name,
            sourceFilePath: path,
            sourceFileType: type,
          );
          lastPage = page;
          importedCount++;
        }
        for (var i = 0; i < pages.length; i++) {
          final (image, pageIndex) = pages[i];
          // Save the rendered page as a PNG file so it persists independently.
          final pageFileName = '${f.name}_page_${pageIndex + 1}.png';
          final pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final pagePath = await import.persistFile(
            pageFileName,
            pngBytes!.buffer.asUint8List(),
          );
          final pageTitle = pages.length == 1
              ? f.name
              : '${f.name} (page ${pageIndex + 1})';
          final page = await app.addPage(
            title: pageTitle,
            sourceFilePath: pagePath,
            sourceFileType: 'image',
            pageIndex: pageIndex,
          );
          lastPage = page;
          importedCount++;
        }
      } else {
        final page = await app.addPage(
          title: f.name,
          sourceFilePath: path,
          sourceFileType: type,
        );
        lastPage = page;
        importedCount++;
        if (type == 'text') {
          // Pre-render imported text as a text annotation so it's not a blank page.
          final text = import.decodeText(f.bytes);
          if (text.trim().isNotEmpty) {
            await app.repo.saveStrokes(page.id, [
              Stroke(
                id: _strokeId(),
                tool: StrokeTool.text,
                color: const Color(0xFF1B365D),
                width: 3,
                text: text,
                start: const Offset(32, 48),
              )
            ]);
          }
        }
      }
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported $importedCount page(s)')),
    );
    // Open the last imported page in the editor right away.
    if (lastPage != null) {
      final lastExt = import.extensionOf(lastPage.title);
      if (lastExt == 'md') {
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MarkdownPreviewScreen(
            page: lastPage!,
            autosave: app.autosave,
          ),
        ));
      } else {
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => EditorScreen(
            page: lastPage!,
            autosave: app.autosave,
          ),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, app, _) {
      final isWide = MediaQuery.of(context).size.width >= 840;
      if (isWide) {
        return Row(
          children: [
            SizedBox(width: 300, child: _NotebookPanel(app: app)),
            const VerticalDivider(width: 1, thickness: 1),
            SizedBox(width: 280, child: _SectionPanel(app: app)),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: _PageListPanel(app: app, onImport: () => _importFiles(context, app))),
          ],
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: const Text('Noteflow'),
          actions: [
            _ThemeMenu(app: app),
            _MaintenanceMenu(app: app),
          ],
        ),
        body: _MobileHome(app: app, onImport: () => _importFiles(context, app)),
      );
    });
  }
}

class _MaintenanceMenu extends StatelessWidget {
  const _MaintenanceMenu({required this.app});
  final AppState app;

  Future<File?> _findDatabaseFile() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final supportDir = await getApplicationSupportDirectory();
      final paths = [
        '${docDir.path}/noteflow.sqlite',
        '${supportDir.path}/noteflow.sqlite',
      ];
      for (final path in paths) {
        final file = File(path);
        if (await file.exists()) {
          return file;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _exportBackup(BuildContext context) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup is not supported in the web version.')),
      );
      return;
    }
    try {
      final dbFile = await _findDatabaseFile();
      if (dbFile == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Database file not found.')),
          );
        }
        return;
      }

      final docs = await getApplicationDocumentsDirectory();
      final importsDir = Directory('${docs.path}${Platform.pathSeparator}noteflow${Platform.pathSeparator}imports');

      final tempDir = await getTemporaryDirectory();
      final zipPath = '${tempDir.path}/noteflow_backup_${DateTime.now().millisecondsSinceEpoch}.noteflow';

      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      encoder.addFile(dbFile, 'noteflow.sqlite');
      if (await importsDir.exists()) {
        await encoder.addDirectory(importsDir);
      }
      encoder.close();

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zipPath)],
          subject: 'Noteflow Backup',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restore is not supported in the web version.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Restore'),
        content: const Text(
          'WARNING: Restoring a backup will overwrite and permanently delete all your current notebooks, notes, and imported documents. This action cannot be undone.\n\nAre you sure you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Restore'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['noteflow', 'zip'],
      );

      if (result == null || result.files.single.path == null) return;
      final backupPath = result.files.single.path!;

      final dbFile = await _findDatabaseFile();
      if (dbFile == null) {
        throw StateError('Cannot locate target database file path.');
      }

      // Close connection
      await app.repo.closeDatabase();

      // Extract backup
      final bytes = await File(backupPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final docs = await getApplicationDocumentsDirectory();
      final importsDir = Directory('${docs.path}${Platform.pathSeparator}noteflow${Platform.pathSeparator}imports');
      if (await importsDir.exists()) {
        await importsDir.delete(recursive: true);
      }
      await importsDir.create(recursive: true);

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          if (filename == 'noteflow.sqlite') {
            await File(dbFile.path).writeAsBytes(data, flush: true);
          } else if (filename.startsWith('imports/')) {
            final relativePath = filename.substring('imports/'.length);
            final targetPath = '${importsDir.path}${Platform.pathSeparator}$relativePath';
            final targetFile = File(targetPath);
            await targetFile.create(recursive: true);
            await targetFile.writeAsBytes(data, flush: true);
          }
        }
      }

      if (context.mounted) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Restore Completed'),
            content: const Text(
              'Database and imports have been restored successfully. The application will now close to reload the new database files.',
            ),
            actions: [
              FilledButton(
                onPressed: () => exit(0),
                child: const Text('Close App'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.settings_backup_restore),
      tooltip: 'Backup / Restore',
      onSelected: (val) {
        if (val == 'backup') {
          _exportBackup(context);
        } else if (val == 'restore') {
          _importBackup(context);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'backup',
          child: Row(
            children: [
              Icon(Icons.backup_outlined),
              SizedBox(width: 8),
              Text('Backup to file'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'restore',
          child: Row(
            children: [
              Icon(Icons.restore_outlined),
              SizedBox(width: 8),
              Text('Restore from file'),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------- Theme menu ----------
class _ThemeMenu extends StatelessWidget {
  const _ThemeMenu({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
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
                Text(_themeLabel(m)),
              ],
            ),
          ),
      ],
    );
  }

  String _themeLabel(AppThemeMode m) => switch (m) {
        AppThemeMode.light => 'Light (paper)',
        AppThemeMode.sepia => 'Sepia',
        AppThemeMode.dark => 'Dark',
        AppThemeMode.amoled => 'AMOLED black',
      };
}

// ---------- Notebooks panel ----------
class _NotebookPanel extends StatelessWidget {
  const _NotebookPanel({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Text('Notebooks', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'New notebook',
                  onPressed: () => promptName(context, 'New notebook',
                      onSubmit: (name) {
                        if (name.isNotEmpty) app.addNotebook(name);
                      }),
                ),
                _ThemeMenu(app: app),
                _MaintenanceMenu(app: app),
              ],
            ),
          ),
          Expanded(
            child: app.notebooks.isEmpty
                ? Center(
                    child: Text('Create your first notebook.',
                        style: TextStyle(color: scheme.onSurfaceVariant)))
                : ListView.builder(
                    itemCount: app.notebooks.length,
                    itemBuilder: (context, i) {
                      final n = app.notebooks[i];
                      final selected = app.notebook?.id == n.id;
                      return ListTile(
                        leading: Icon(Icons.menu_book_outlined,
                            color: selected ? scheme.primary : scheme.onSurfaceVariant),
                        title: Text(n.name),
                        selected: selected,
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'rename') {
                              promptName(context, 'Rename notebook',
                                  initial: n.name, submitLabel: 'Rename',
                                  onSubmit: (name) {
                                    if (name.isNotEmpty) app.renameNotebook(n.id, name);
                                  });
                            }
                            if (v == 'delete') {
                              confirmDelete(context, 'Delete notebook "${n.name}"?',
                                  'All sections and pages inside will be permanently deleted.',
                                  () => app.deleteNotebook(n.id));
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'rename', child: Text('Rename')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                        onTap: () => app.selectNotebook(n.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------- Shared dialog helpers ----------
void promptName(BuildContext context, String title,
    {String? initial, String submitLabel = 'Create', required ValueChanged<String> onSubmit}) {
  final controller = TextEditingController(text: initial ?? '');
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            onSubmit(controller.text.trim());
            Navigator.pop(ctx);
          },
          child: Text(submitLabel),
        ),
      ],
    ),
  );
}

void confirmDelete(BuildContext context, String title, String body, VoidCallback onConfirm) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            onConfirm();
            Navigator.pop(ctx);
          },
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

// ---------- Sections panel ----------
class _SectionPanel extends StatelessWidget {
  const _SectionPanel({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Text('Sections', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'New section',
                  onPressed: () => promptName(context, 'New section', onSubmit: (name) {
                    if (name.isNotEmpty) app.addSection(name);
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: app.sections.isEmpty
                ? Center(
                    child: Text('No sections in this notebook.',
                        style: TextStyle(color: scheme.onSurfaceVariant)))
                : ListView.builder(
                    itemCount: app.sections.length,
                    itemBuilder: (context, i) {
                      final s = app.sections[i];
                      final selected = app.section?.id == s.id;
                      return ListTile(
                        leading: Icon(Icons.folder_outlined,
                            color: selected ? scheme.primary : scheme.onSurfaceVariant),
                        title: Text(s.name),
                        selected: selected,
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'rename') {
                              promptName(context, 'Rename section',
                                  initial: s.name, submitLabel: 'Rename',
                                  onSubmit: (name) {
                                    if (name.isNotEmpty) app.renameSection(s.id, name);
                                  });
                            }
                            if (v == 'delete') {
                              confirmDelete(context, 'Delete section "${s.name}"?',
                                  'All pages inside will be permanently deleted.',
                                  () => app.deleteSection(s.id));
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'rename', child: Text('Rename')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                        onTap: () => app.selectSection(s.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------- Pages panel ----------
class _PageListPanel extends StatelessWidget {
  const _PageListPanel({required this.app, required this.onImport});
  final AppState app;
  final VoidCallback onImport;

  void _addPageDialog(BuildContext context, AppState app) {
    final titleController = TextEditingController(text: 'Untitled');
    String template = 'blank';

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('New page'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'Enter page title…',
                ),
              ),
              const SizedBox(height: 16),
              const Text('Paper Template', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: template,
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: const [
                  DropdownMenuItem(value: 'blank', child: Text('Blank paper')),
                  DropdownMenuItem(value: 'lined', child: Text('Lined paper')),
                  DropdownMenuItem(value: 'grid', child: Text('Grid paper')),
                  DropdownMenuItem(value: 'dots', child: Text('Dot grid')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => template = val);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleController.text.trim();
                await app.addPage(
                  title: title.isEmpty ? 'Untitled' : title,
                  template: template == 'blank' ? null : template,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Create'),
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(app.section?.name ?? 'Pages',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.history),
                  tooltip: 'Recent',
                  onPressed: () => _openRecent(context, app),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Search',
                  onPressed: () => _openSearch(context, app),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Trash',
                  onPressed: () => _openTrash(context, app),
                ),
                IconButton(
                  icon: const Icon(Icons.file_upload_outlined),
                  tooltip: 'Import file',
                  onPressed: onImport,
                ),
                IconButton(
                  icon: const Icon(Icons.edit_note),
                  tooltip: 'New blank page',
                  onPressed: () => _addPageDialog(context, app),
                ),
              ],
            ),
          ),
          Expanded(
            child: app.pages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.note_add_outlined,
                            size: 56, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text('No pages yet. Import a file or add a blank page.',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: onImport,
                          icon: const Icon(Icons.file_upload_outlined),
                          label: const Text('Import file'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: app.pages.length,
                    itemBuilder: (context, i) {
                      final p = app.pages[i];
                      return _PageTile(page: p, app: app);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openSearch(BuildContext context, AppState app) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SearchSheet(app: app),
    );
  }

  void _openRecent(BuildContext context, AppState app) {
    app.loadRecent();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecentSheet(app: app),
    );
  }

  void _openTrash(BuildContext context, AppState app) {
    app.loadTrash();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TrashSheet(app: app),
    );
  }
}

// ---------- Search ----------
class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.app});
  final AppState app;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  List<NotePage> _results = [];
  bool _loading = false;

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    final r = await widget.app.searchPages(q);
    if (mounted) {
      setState(() {
        _results = r;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Search pages', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Type to search titles…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (q) {
                if (q.trim().isEmpty) {
                  setState(() => _results = []);
                  return;
                }
                _search(q.trim());
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Text('No matching pages.',
                              style: TextStyle(color: scheme.onSurfaceVariant)))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: _results.length,
                          itemBuilder: (context, i) => _PageTile(
                              page: _results[i], app: widget.app),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Recent ----------
class _RecentSheet extends StatelessWidget {
  const _RecentSheet({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, scrollController) => Consumer<AppState>(
        builder: (context, app, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recently opened',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Expanded(
                child: app.recent.isEmpty
                    ? Center(
                        child: Text(
                          'Pages you open will show up here.',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: app.recent.length,
                        itemBuilder: (context, i) => _PageTile(
                            page: app.recent[i], app: app),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Trash ----------
class _TrashSheet extends StatefulWidget {
  const _TrashSheet({required this.app});
  final AppState app;

  @override
  State<_TrashSheet> createState() => _TrashSheetState();
}

class _TrashSheetState extends State<_TrashSheet> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, scrollController) => Consumer<AppState>(
        builder: (context, app, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Trash', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: app.trashed.isEmpty
                        ? null
                        : () {
                            confirmDelete(
                                context, 'Empty trash?',
                                'All trashed pages will be permanently deleted.',
                                () => app.emptyTrash());
                          },
                    child: const Text('Empty trash'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: app.trashed.isEmpty
                    ? Center(
                        child: Text('Trash is empty.',
                            style: TextStyle(color: scheme.onSurfaceVariant)))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: app.trashed.length,
                        itemBuilder: (context, i) {
                          final p = app.trashed[i];
                          return ListTile(
                            leading: Icon(Icons.description_outlined,
                                color: scheme.onSurfaceVariant),
                            title: Text(p.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(_relative(p.updatedAt),
                                style: const TextStyle(fontSize: 12)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Restore',
                                  icon: const Icon(Icons.restore),
                                  onPressed: () => app.restorePage(p.id),
                                ),
                                IconButton(
                                  tooltip: 'Delete forever',
                                  icon: const Icon(Icons.delete_forever),
                                  onPressed: () => app.deletePage(p.id),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _relative(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${t.toLocal().day}/${t.toLocal().month}/${t.toLocal().year}';
}

class _PageTile extends StatelessWidget {
  const _PageTile({required this.page, required this.app});
  final NotePage page;
  final AppState app;

  IconData _iconName() => switch (page.sourceFileType) {
        'pdf' => Icons.picture_as_pdf_outlined,
        'image' => Icons.image_outlined,
        'text' => Icons.notes,
        _ => Icons.description_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = app.page?.id == page.id;
    return ListTile(
      leading: Icon(_iconName(),
          color: selected ? scheme.primary : scheme.onSurfaceVariant),
      title: Text(page.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_relative(page.updatedAt), style: const TextStyle(fontSize: 12)),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'pin') app.togglePin(page.id);
          if (v == 'rename') _rename(context);
          if (v == 'trash') app.trashPage(page.id);
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'pin',
              child: Text(page.pinned ? 'Unpin' : 'Pin to top')),
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          const PopupMenuItem(value: 'trash', child: Text('Move to trash')),
        ],
      ),
      onTap: () {
        if (app.page?.id == page.id) return;
        _openEditor(context);
      },
    );
  }

  void _openEditor(BuildContext context) {
    final importer = ImportService();
    final ext = importer.extensionOf(page.title);
    if (ext == 'md') {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MarkdownPreviewScreen(
          page: page,
          autosave: app.autosave,
        ),
      ));
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => EditorScreen(
          page: page,
          autosave: app.autosave,
        ),
      ));
    }
  }

  void _rename(BuildContext context) {
    final controller = TextEditingController(text: page.title);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename page'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              app.renamePage(page.id, controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}

// ---------- Mobile layout ----------
class _MobileHome extends StatelessWidget {
  const _MobileHome({required this.app, required this.onImport});
  final AppState app;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.menu_book_outlined), text: 'Notebooks'),
              Tab(icon: Icon(Icons.folder_outlined), text: 'Sections'),
              Tab(icon: Icon(Icons.description_outlined), text: 'Pages'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _NotebookPanel(app: app),
                _SectionPanel(app: app),
                _PageListPanel(app: app, onImport: onImport),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
