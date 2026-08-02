import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/stroke.dart';
import '../theme/app_theme.dart';

class AnnotationCanvas extends StatefulWidget {
  const AnnotationCanvas({
    super.key,
    required this.tool,
    required this.color,
    required this.width,
    required this.initialStrokes,
    this.backgroundImage,
    this.onChanged,
  });

  final StrokeTool tool;
  final Color color;
  final double width;
  final List<Stroke> initialStrokes;
  final ui.Image? backgroundImage;
  final ValueChanged<List<Stroke>>? onChanged;

  @override
  State<AnnotationCanvas> createState() => AnnotationCanvasState();
}

class AnnotationCanvasState extends State<AnnotationCanvas> {
  final TransformationController _transform = TransformationController();
  late List<Stroke> _strokes = List.of(widget.initialStrokes);
  final List<List<Stroke>> _undo = [];
  final List<List<Stroke>> _redo = [];

  // Current in-progress stroke
  List<Offset>? _points;
  Offset? _dragStart;

  @override
  void initState() {
    super.initState();
    _strokes = List.of(widget.initialStrokes);
  }

  @override
  void didUpdateWidget(covariant AnnotationCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.initialStrokes, widget.initialStrokes)) {
      _strokes = List.of(widget.initialStrokes);
    }
  }

  Offset _canvasPoint(Offset local) {
    final m = _transform.value.clone()..invert();
    return MatrixUtils.transformPoint(m, local);
  }

  void _beginStroke(Offset local) {
    final p = _canvasPoint(local);
    _points = [p];
    _dragStart = p;
  }

  void _continueStroke(Offset local) {
    final p = _canvasPoint(local);
    _points!.add(p);
    setState(() {});
  }

  void _endStroke(double pressure) {
    if (_points == null) return;
    final tool = widget.tool;
    List<Stroke> produced;
    if (tool == StrokeTool.eraser) {
      _erase(_points!);
      produced = [];
    } else if (tool == StrokeTool.pen || tool == StrokeTool.highlighter) {
      produced = [
        Stroke(
          id: _strokeId(),
          tool: tool,
          color: widget.color,
          width: widget.width * (1 + pressure),
          points: List.of(_points!),
        )
      ];
    } else if (tool == StrokeTool.text) {
      produced = [];
    } else {
      // shapes: rect, line, arrow, ellipse
      produced = [
        Stroke(
          id: _strokeId(),
          tool: tool,
          color: widget.color,
          width: widget.width,
          filled: false,
          start: _dragStart,
          end: _points!.last,
        )
      ];
    }
    _commit(produced);
    _points = null;
    _dragStart = null;
  }

  void _commit(List<Stroke> newStrokes) {
    _undo.add(List.of(_strokes));
    if (_undo.length > 200) _undo.removeAt(0);
    _redo.clear();
    _strokes.addAll(newStrokes);
    setState(() {});
    widget.onChanged?.call(_strokes);
  }

  void _erase(List<Offset> eraserPath) {
    _undo.add(List.of(_strokes));
    _redo.clear();
    _strokes = _strokes.where((s) => !_hitTest(eraserPath, s)).toList();
    setState(() {});
    widget.onChanged?.call(_strokes);
  }

  bool _hitTest(List<Offset> path, Stroke s) {
    final radius = widget.width;
    for (final p in s.points) {
      for (final e in path) {
        if ((p - e).distance <= radius + s.width / 2) return true;
      }
    }
    if (s.start != null && s.end != null) {
      for (final e in path) {
        if (_segmentDistance(s.start!, s.end!, e) <= radius + s.width / 2) return true;
      }
    }
    return false;
  }

  double _segmentDistance(Offset a, Offset b, Offset p) {
    final ab = b - a;
    final lengthSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSq == 0) return (p - a).distance;
    var t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lengthSq;
    t = t.clamp(0.0, 1.0);
    final proj = a + ab * t;
    return (p - proj).distance;
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(List.of(_strokes));
    _strokes = _undo.removeLast();
    setState(() {});
    widget.onChanged?.call(_strokes);
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(List.of(_strokes));
    _strokes = _redo.removeLast();
    setState(() {});
    widget.onChanged?.call(_strokes);
  }

  void clear() {
    _commit([]);
  }

  void setStrokes(List<Stroke> strokes) {
    _strokes = List.of(strokes);
    _undo.clear();
    _redo.clear();
    setState(() {});
    widget.onChanged?.call(_strokes);
  }

  List<Stroke> get strokes => _strokes;

  String _strokeId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  void _zoomAt(Offset focal, double scale) {
    final newMatrix = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
    _transform.value = newMatrix;
  }

  void zoomIn() => _zoomAt(Offset.zero, 1.2);
  void zoomOut() => _zoomAt(Offset.zero, 1 / 1.2);
  void fit() => _transform.value = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    final canvasColor = Theme.of(context).scaffoldBackgroundColor;
    return ClipRect(
      child: LayoutBuilder(builder: (context, constraints) {
        return InteractiveViewer(
          transformationController: _transform,
          constrained: true,
          minScale: 0.1,
          maxScale: 8,
          panEnabled: widget.tool == StrokeTool.select,
          scaleEnabled: widget.tool == StrokeTool.select,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              if (widget.tool == StrokeTool.text) {
                _beginText(d.localPosition);
              }
            },
            onPanStart: (d) {
              if (widget.tool == StrokeTool.select) return;
              _beginStroke(d.localPosition);
            },
            onPanUpdate: (d) {
              if (widget.tool == StrokeTool.select) return;
              _continueStroke(d.localPosition);
            },
            onPanEnd: (d) {
              if (widget.tool == StrokeTool.select) return;
              _endStroke(d.velocity.pixelsPerSecond.distance > 0 ? 1.0 : 0.0);
            },
            child: SizedBox(
              width: 1200,
              height: 1600,
              child: CustomPaint(
                painter: _CanvasPainter(
                  strokes: _strokes,
                  inProgress: _inProgressStroke(),
                  backgroundImage: widget.backgroundImage,
                  palette: PaperPalette.of(
                      themeModeOf(Theme.of(context).colorScheme)),
                  canvasColor: canvasColor,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Stroke? _inProgressStroke() {
    if (_points == null || _points!.isEmpty) return null;
    final tool = widget.tool;
    if (tool == StrokeTool.pen || tool == StrokeTool.highlighter) {
      return Stroke(
        id: 'pending',
        tool: tool,
        color: widget.color,
        width: widget.width,
        points: _points!,
      );
    }
    if (tool == StrokeTool.rect ||
        tool == StrokeTool.line ||
        tool == StrokeTool.arrow ||
        tool == StrokeTool.ellipse) {
      if (_dragStart == null || _points == null || _points!.isEmpty) return null;
      return Stroke(
        id: 'pending',
        tool: tool,
        color: widget.color,
        width: widget.width,
        start: _dragStart,
        end: _points!.last,
      );
    }
    return null;
  }

  void _beginText(Offset local) {
    final p = _canvasPoint(local);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Add text'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Type note text…'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) {
                  _commit([
                    Stroke(
                      id: _strokeId(),
                      tool: StrokeTool.text,
                      color: widget.color,
                      width: widget.width,
                      text: ctrl.text,
                      start: p,
                    )
                  ]);
                }
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter({
    required this.strokes,
    required this.inProgress,
    required this.backgroundImage,
    required this.palette,
    required this.canvasColor,
  });

  final List<Stroke> strokes;
  final Stroke? inProgress;
  final ui.Image? backgroundImage;
  final PaperPalette palette;
  final Color canvasColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = canvasColor,
    );

    if (backgroundImage != null) {
      final fit = _containFit(backgroundImage!, size);
      canvas.drawImageRect(
        backgroundImage!,
        Rect.fromLTWH(
            0, 0, backgroundImage!.width.toDouble(), backgroundImage!.height.toDouble()),
        fit,
        Paint()..filterQuality = FilterQuality.high,
      );
    }

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.02)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final all = [...strokes, if (inProgress != null) inProgress!];
    for (final s in all) {
      _paintStroke(canvas, s);
    }
  }

  Rect _containFit(ui.Image image, Size target) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();
    final scale = math.min(target.width / imgW, target.height / imgH);
    final w = imgW * scale;
    final h = imgH * scale;
    return Rect.fromCenter(
      center: Offset(target.width / 2, target.height / 2),
      width: w,
      height: h,
    );
  }

  void _paintStroke(Canvas canvas, Stroke s) {
    final isHighlight = s.tool == StrokeTool.highlighter;
    final paint = Paint()
      ..color = isHighlight
          ? s.color.withValues(alpha: 0.45)
          : s.color
      ..strokeWidth = s.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (isHighlight) {
      paint.blendMode = BlendMode.multiply;
    }

    switch (s.tool) {
      case StrokeTool.pen:
      case StrokeTool.highlighter:
        if (s.points.isEmpty) break;
        final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
        for (final p in s.points.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      case StrokeTool.text:
        final tp = TextPainter(
          text: TextSpan(
            text: s.text,
            style: TextStyle(
              color: s.color,
              fontSize: math.max(12, s.width * 4),
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, s.start ?? Offset.zero);
      case StrokeTool.rect:
        if (s.start != null && s.end != null) {
          canvas.drawRect(Rect.fromPoints(s.start!, s.end!), paint);
        }
      case StrokeTool.ellipse:
        if (s.start != null && s.end != null) {
          canvas.drawOval(Rect.fromPoints(s.start!, s.end!), paint);
        }
      case StrokeTool.line:
        if (s.start != null && s.end != null) {
          canvas.drawLine(s.start!, s.end!, paint);
        }
      case StrokeTool.arrow:
        if (s.start != null && s.end != null) {
          _paintArrow(canvas, s.start!, s.end!, paint);
        }
      case StrokeTool.eraser:
      case StrokeTool.select:
        break;
    }
  }

  void _paintArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final head = math.max(8.0, paint.strokeWidth * 3);
    for (final d in [-math.pi / 6, math.pi / 6]) {
      final tip = Offset(
        end.dx - head * math.cos(angle + d),
        end.dy - head * math.sin(angle + d),
      );
      canvas.drawLine(end, tip, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) =>
      old.strokes != strokes ||
      old.inProgress != inProgress ||
      old.backgroundImage != backgroundImage ||
      old.palette != palette ||
      old.canvasColor != canvasColor;
}

