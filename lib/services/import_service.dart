import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// Handles importing files (PDF, images, text) into the app's private storage
/// and preparing them for use as a canvas.
class ImportService {
  /// Pick one or more files via the system picker (SAF on Android).
  Future<List<ImportedFile>> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'txt', 'md'],
      withData: true,
    );
    if (result == null) return [];
    return result.files
        .where((f) => f.bytes != null)
        .map((f) => ImportedFile(name: f.name, bytes: f.bytes!, size: f.size))
        .toList();
  }

  String extensionOf(String name) {
    final i = name.lastIndexOf('.');
    return i >= 0 ? name.substring(i + 1).toLowerCase() : '';
  }

  bool isImage(String ext) =>
      const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'].contains(ext);
  bool isPdf(String ext) => ext == 'pdf';
  bool isText(String ext) => const ['txt', 'md'].contains(ext);

  Future<ui.Image> decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Loads a page background image from the app's stored file path.
  Future<ui.Image?> loadPageImage(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }
}

class ImportedFile {
  final String name;
  final Uint8List bytes;
  final int size;
  const ImportedFile({required this.name, required this.bytes, required this.size});
}
