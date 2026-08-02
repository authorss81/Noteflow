import 'dart:async';
import 'dart:convert';
import 'package:archive/archive_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PluginLoaderService {
  final SharedPreferences prefs;
  PluginLoaderService(this.prefs);

  /// Checks if a dynamic plugin is installed.
  bool isPluginInstalled(String pluginId) {
    return prefs.getBool('plugin_installed_$pluginId') ?? false;
  }

  /// Simulates downloading and installing a dynamic plugin with progress callbacks.
  Stream<double> downloadPlugin(String pluginId) async* {
    double progress = 0.0;
    while (progress < 1.0) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      progress += 0.1;
      if (progress > 1.0) progress = 1.0;
      yield progress;
    }
    await prefs.setBool('plugin_installed_$pluginId', true);
  }

  /// Uninstalls/removes a plugin.
  Future<void> uninstallPlugin(String pluginId) async {
    await prefs.remove('plugin_installed_$pluginId');
  }

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
