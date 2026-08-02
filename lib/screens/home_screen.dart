import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note_models.dart';
import '../services/import_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'editor_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _importFiles(BuildContext context, AppState app) async {
    final import = ImportService();
    final files = await import.pickFiles();
    if (files.isEmpty) return;
    for (final f in files) {
      final ext = import.extensionOf(f.name);
      await app.addPage(
        title: f.name,
        sourceFilePath: null, // placeholder; MVP stores name only
        sourceFileType: import.isPdf(ext) ? 'pdf' : import.isImage(ext) ? 'image' : 'text',
      );
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${files.length} file(s)')),
      );
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
          actions: [_ThemeMenu(app: app)],
        ),
        body: _MobileHome(app: app, onImport: () => _importFiles(context, app)),
      );
    });
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
                  onPressed: () => _promptName(context, 'New notebook', (name) {
                    app.addNotebook(name);
                  }),
                ),
                _ThemeMenu(app: app),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: app.notebooks.length,
              itemBuilder: (context, i) {
                final n = app.notebooks[i];
                final selected = app.notebook?.id == n.id;
                return ListTile(
                  leading: Icon(Icons.menu_book_outlined,
                      color: selected ? scheme.primary : scheme.onSurfaceVariant),
                  title: Text(n.name),
                  selected: selected,
                  onTap: () => app.selectNotebook(n.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _promptName(BuildContext context, String title, ValueChanged<String> onSubmit) {
    final controller = TextEditingController();
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
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
                  onPressed: () => _promptName(context, 'New section', (name) {
                    app.addSection(name);
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: app.sections.length,
              itemBuilder: (context, i) {
                final s = app.sections[i];
                final selected = app.section?.id == s.id;
                return ListTile(
                  leading: Icon(Icons.folder_outlined,
                      color: selected ? scheme.primary : scheme.onSurfaceVariant),
                  title: Text(s.name),
                  selected: selected,
                  onTap: () => app.selectSection(s.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _promptName(BuildContext context, String title, ValueChanged<String> onSubmit) {
    final controller = TextEditingController();
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
            child: const Text('Create'),
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
                  icon: const Icon(Icons.file_upload_outlined),
                  tooltip: 'Import file',
                  onPressed: onImport,
                ),
                IconButton(
                  icon: const Icon(Icons.edit_note),
                  tooltip: 'New blank page',
                  onPressed: () => app.addPage(),
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
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EditorScreen(
        page: page,
        autosave: app.autosave,
      ),
    ));
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

  String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${t.toLocal().day}/${t.toLocal().month}/${t.toLocal().year}';
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
