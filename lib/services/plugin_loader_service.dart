import 'dart:convert';
import 'package:archive/archive_io.dart';

class PluginLoaderService {
  /// Converts a DOCX file to Markdown text natively by parsing the inner w:t XML nodes.
  static String convertDocxToMarkdown(List<int> docxBytes) {
    try {
      final archive = ZipDecoder().decodeBytes(docxBytes);
      final documentFile = archive.findFile('word/document.xml');
      if (documentFile == null) {
        throw StateError('Cannot locate word/document.xml in ZIP archive.');
      }

      final xmlContent = utf8.decode(documentFile.content as List<int>);
      
      // Extract text content inside <w:t> tags
      final regex = RegExp(r'<w:t[^>]*>(.*?)</w:t>');
      final matches = regex.allMatches(xmlContent);
      
      final sb = StringBuffer();
      sb.writeln('# Converted Word Document\n');
      
      var count = 0;
      for (final match in matches) {
        final text = match.group(1);
        if (text != null) {
          sb.write(text);
          count++;
          if (count % 10 == 0) {
            sb.writeln('\n'); // Add paragraph break
          }
        }
      }
      return sb.toString();
    } catch (e) {
      return '### Document Conversion Error\nFailed to parse docx document: $e';
    }
  }
}
