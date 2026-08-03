import 'dart:ui' show Color, Offset;

import 'package:flutter/foundation.dart';

enum StrokeTool { pen, highlighter, eraser, text, rect, line, arrow, ellipse, select }

extension StrokeToolName on StrokeTool {
  String get label => switch (this) {
        StrokeTool.pen => 'Pen',
        StrokeTool.highlighter => 'Highlighter',
        StrokeTool.eraser => 'Eraser',
        StrokeTool.text => 'Text',
        StrokeTool.rect => 'Rectangle',
        StrokeTool.line => 'Line',
        StrokeTool.arrow => 'Arrow',
        StrokeTool.ellipse => 'Ellipse',
        StrokeTool.select => 'Select',
      };
}

/// A single annotation element on a page.
@immutable
class Stroke {
  final String id;
  final StrokeTool tool;
  final Color color;
  final double width;
  final bool filled;
  final String text;
  final List<Offset> points;
  final Offset? start;
  final Offset? end;

  /// PDF page (0-based) this annotation belongs to. Always 0 for non-PDF
  /// pages. Lets a single PDF [Stroke] set keep per-page annotations (R1-22).
  final int page;

  const Stroke({
    required this.id,
    required this.tool,
    required this.color,
    this.width = 3,
    this.filled = false,
    this.text = '',
    this.points = const [],
    this.start,
    this.end,
    this.page = 0,
  });

  Stroke copyWith({
    StrokeTool? tool,
    Color? color,
    double? width,
    bool? filled,
    String? text,
    List<Offset>? points,
    Offset? start,
    Offset? end,
    int? page,
  }) {
    return Stroke(
      id: id,
      tool: tool ?? this.tool,
      color: color ?? this.color,
      width: width ?? this.width,
      filled: filled ?? this.filled,
      text: text ?? this.text,
      points: points ?? this.points,
      start: start ?? this.start,
      end: end ?? this.end,
      page: page ?? this.page,
    );
  }

  /// Serialize to JSON for persistence in SQLite.
  Map<String, Object?> toJson() => {
        'id': id,
        'tool': tool.name,
        'color': color.toARGB32(),
        'width': width,
        'filled': filled ? 1 : 0,
        'text': text,
        'points': points.map((p) => [p.dx, p.dy]).toList(),
        'start': start == null ? null : [start!.dx, start!.dy],
        'end': end == null ? null : [end!.dx, end!.dy],
        'page': page,
      };

  static Stroke fromJson(Map<String, Object?> json) {
    final rawPoints = (json['points'] as List?)?.cast<List<dynamic>>() ?? [];
    return Stroke(
      id: json['id'] as String,
      tool: StrokeTool.values.firstWhere(
        (t) => t.name == json['tool'],
        orElse: () => StrokeTool.pen,
      ),
      color: Color(json['color'] as int),
      width: (json['width'] as num?)?.toDouble() ?? 3,
      filled: (json['filled'] as int? ?? 0) == 1,
      text: json['text'] as String? ?? '',
      points: rawPoints
          .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList(),
      start: _toOffset(json['start']),
      end: _toOffset(json['end']),
      page: json['page'] as int? ?? 0,
    );
  }

  static Offset? _toOffset(Object? v) {
    if (v is! List) return null;
    return Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
  }
}
