import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../models/stroke.dart';

class PdfToolService {
  /// Renders a list of strokes onto a dynamic picture and returns the PNG bytes.
  static Future<Uint8List> renderStrokesToPng(List<Stroke> strokes, {double width = 800, double height = 1100}) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, width, height));

    // Draw background (white)
    final bgPaint = ui.Paint()..color = Colors.white;
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, width, height), bgPaint);

    // Draw each stroke
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      
      if (stroke.tool == StrokeTool.text) {
        // Draw text annotation
        final textPainter = TextPainter(
          text: TextSpan(
            text: stroke.text,
            style: TextStyle(color: stroke.color, fontSize: 16),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(maxWidth: width - stroke.points.first.dx);
        textPainter.paint(canvas, Offset(stroke.points.first.dx, stroke.points.first.dy));
      } else {
        // Draw lines
        final paint = ui.Paint()
          ..color = stroke.color
          ..strokeWidth = stroke.width
          ..strokeCap = ui.StrokeCap.round
          ..strokeJoin = ui.StrokeJoin.round
          ..style = ui.PaintingStyle.stroke;
          
        final path = ui.Path();
        path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (var i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return pngBytes!.buffer.asUint8List();
  }

  /// Merges multiple note pages' strokes into a single multi-page PDF document.
  static Future<File> mergePagesToPdf(List<List<Stroke>> allPagesStrokes, String filename) async {
    final pdf = pw.Document();
    for (final strokes in allPagesStrokes) {
      final pngBytes = await renderStrokesToPng(strokes);
      final image = pw.MemoryImage(pngBytes);
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
    }
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}
