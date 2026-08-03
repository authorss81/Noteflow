import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'encryption_service.dart';

/// Handles importing files (PDF, images, text) into the app's private storage
/// and preparing them for use as a canvas.
///
/// Imported files are encrypted at rest with the app's DEK when a master
/// password is set (R1-10): the stored bytes are AES-GCM ciphertext and every
/// read path decrypts on demand.
class ImportService {
  ImportService({SecretKey? Function()? keyProvider})
      : _keyProvider = keyProvider;

  final SecretKey? Function()? _keyProvider;

  Future<Uint8List> _encryptForStorage(Uint8List bytes) async {
    final key = _keyProvider?.call();
    if (key == null) return bytes;
    return Uint8List.fromList(await EncryptionService.encryptBytes(bytes, key));
  }

  /// Reads a stored file, decrypting it when it was written while a master
  /// password was active. Legacy plaintext files are returned untouched.
  Future<Uint8List> readDecryptedBytes(String path) async {
    final file = File(path);
    final raw = await file.readAsBytes();
    final key = _keyProvider?.call();
    if (key == null) return raw;
    try {
      final dec = Uint8List.fromList(
          await EncryptionService.decryptBytes(raw, key));
      if (_looksLikeImportFile(dec)) return dec;
    } catch (_) {
      // Not ciphertext under this key (e.g. legacy plaintext file).
    }
    return raw;
  }

  /// Magic-byte check so we only trust decrypted output that looks like an
  /// actual imported file (PDF, image, or text). If decrypting a legacy
  /// plaintext file ever succeeded by chance, this still guards the format.
  static bool _looksLikeImportFile(Uint8List bytes) {
    bool ascii(int start, int len, String s) {
      for (var i = 0; i < len; i++) {
        if (bytes[start + i] != s.codeUnitAt(i)) return false;
      }
      return true;
    }

    if (bytes.length >= 5 && ascii(0, 4, '%PDF')) return true; // PDF
    if (bytes.length >= 8 && ascii(1, 3, 'PNG')) return true; // PNG
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true; // JPEG
    }
    if (bytes.length >= 4 && ascii(0, 3, 'GIF')) return true; // GIF
    if (bytes.length >= 2 && ascii(0, 2, 'BM')) return true; // BMP
    if (bytes.length >= 12 && ascii(0, 4, 'RIFF') && ascii(8, 4, 'WEBP')) {
      return true; // WEBP
    }
    return true; // treat anything else as text-like
  }

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

  /// Copies imported file bytes into the app's documents directory and
  /// returns the persistent path (survives app restarts; safe on Android).
  /// Bytes are encrypted at rest when a master password is active (R1-10).
  Future<String> persistFile(String name, Uint8List bytes) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}noteflow'
        '${Platform.pathSeparator}imports');
    await dir.create(recursive: true);
    final path = '${dir.path}${Platform.pathSeparator}${_stamp()}_$name';
    await File(path).writeAsBytes(await _encryptForStorage(bytes), flush: true);
    return path;
  }

  /// Deletes a stored imported file, ignoring errors.
  Future<void> deleteStoredFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  String _stamp() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

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

  /// Loads a page background image from the app's stored file path
  /// (decrypting it first when it was stored encrypted).
  Future<ui.Image?> loadPageImage(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await readDecryptedBytes(path);
      return decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Loads a page background for any supported source type (image or PDF).
  Future<ui.Image?> loadBackground(String path, String type) async {
    if (type == 'pdf') return loadPdfPage(path);
    return loadPageImage(path);
  }

/// Renders the first page of a PDF to an image (PDFium does the rendering
/// via pdfrx; raw BGRA pixels are converted to a ui.Image). Decrypts the
/// stored PDF bytes first when needed (R1-10). Render resolution is capped to
/// bound memory on large/native-res PDFs (R1-15).
Future<ui.Image?> loadPdfPage(String path) async {
  PdfDocument? doc;
  try {
    final bytes = await readDecryptedBytes(path);
    doc = await PdfDocument.openData(bytes);
    final pages = doc.pages;
    if (pages.isEmpty) return null;
    final page = pages.first;
    if (!page.isLoaded) return null;
    final (w, h) = _cappedSize(page.width, page.height);
    final rendered = await page.render(width: w, height: h);
    if (rendered == null) return null;
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rendered.pixels,
      rendered.width,
      rendered.height,
      ui.PixelFormat.bgra8888,
      completer.complete,
    );
    final image = await completer.future;
    rendered.dispose();
    return image;
  } catch (_) {
    return null;
  } finally {
    await doc?.dispose();
  }
}

/// Renders all pages of a PDF to images, returning (image, pageIndex) pairs.
/// Uses pdfrx to render each page at its native resolution. Decrypts the
/// stored PDF bytes first when needed (R1-10). Resolution is capped to bound
/// total memory when a PDF has many high-res pages (R1-15).
Future<List<(ui.Image, int)>> loadPdfPages(String path) async {
  PdfDocument? doc;
  try {
    final bytes = await readDecryptedBytes(path);
    doc = await PdfDocument.openData(bytes);
    final pages = doc.pages;
    final results = <(ui.Image, int)>[];
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      if (!page.isLoaded) continue;
      final (w, h) = _cappedSize(page.width, page.height);
      final rendered = await page.render(width: w, height: h);
      if (rendered == null) continue;
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rendered.pixels,
        rendered.width,
        rendered.height,
        ui.PixelFormat.bgra8888,
        completer.complete,
      );
      final image = await completer.future;
      rendered.dispose();
      results.add((image, i));
    }
    return results;
  } catch (_) {
    return [];
  } finally {
    await doc?.dispose();
  }
}

/// Caps the long edge of a PDF page at [_maxRenderDim] logical pixels so a
/// single page can never allocate unbounded raster memory.
(int, int) _cappedSize(double width, double height) {
  const maxDim = 1600.0;
  final long = width > height ? width : height;
  if (long <= maxDim || long <= 0) return (width.round(), height.round());
  final scale = maxDim / long;
  return ((width * scale).round(), (height * scale).round());
}

  /// Decodes text file bytes (handles BOM + UTF-8).
  String decodeText(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    return text;
  }
}

class ImportedFile {
  final String name;
  final Uint8List bytes;
  final int size;
  const ImportedFile({required this.name, required this.bytes, required this.size});
}
