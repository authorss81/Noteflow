import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../models/note_models.dart';
import '../services/import_service.dart';
import '../theme/app_theme.dart';
import 'editor_screen.dart';

class MarkdownPreviewScreen extends StatefulWidget {
  const MarkdownPreviewScreen({super.key, required this.page, required this.autosave});

  final NotePage page;
  final AutosaveService autosave;

  @override
  State<MarkdownPreviewScreen> createState() => _MarkdownPreviewScreenState();
}

class _MarkdownPreviewScreenState extends State<MarkdownPreviewScreen> {
  String _text = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadText();
  }

  Future<void> _loadText() async {
    final path = widget.page.sourceFilePath;
    if (path == null) {
      setState(() {
        _loading = false;
        _text = '';
      });
      return;
    }
    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final import = ImportService();
        setState(() {
          _text = import.decodeText(bytes);
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _text = '';
        });
      }
    } catch (_) {
      setState(() {
        _loading = false;
        _text = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(widget.page.title),
        actions: [
          IconButton(
            tooltip: 'Edit in canvas',
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EditorScreen(
                  page: widget.page,
                  autosave: widget.autosave,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _text.isEmpty
                  ? Center(
                      child: Text(
                        'No text content to preview.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : MarkdownBody(
                      data: _text,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(color: scheme.onSurface),
                        h1: TextStyle(
                          color: scheme.primary,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                        h2: TextStyle(
                          color: scheme.primary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        h3: TextStyle(
                          color: scheme.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        code: TextStyle(
                          backgroundColor: scheme.surfaceContainerHighest,
                          fontFamily: 'monospace',
                        ),
                        blockquote: TextStyle(
                          color: scheme.onSurfaceVariant,
                          borderLeft: BorderSide(
                            color: scheme.primary,
                            width: 3,
                          ),
                        ),
                        listBullet: TextStyle(color: scheme.onSurface),
                        tableHead: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
    );
  }
}