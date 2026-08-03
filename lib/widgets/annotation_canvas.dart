import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stroke.dart';
import '../theme/app_theme.dart';
import '../core/ids.dart';

class AnnotationCanvas extends StatefulWidget {
  const AnnotationCanvas({
    super.key,
    required this.tool,
    required this.color,
    required this.width,
    required this.initialStrokes,
    this.backgroundImage,
    this.template,
    this.onChanged,
    this.page = 0,
  });

  final StrokeTool tool;
  final Color color;
  final double width;
  final List<Stroke> initialStrokes;
  final ui.Image? backgroundImage;
  final String? template;
  final ValueChanged<List<Stroke>>? onChanged;

  /// PDF page (0-based) that newly drawn strokes belong to (R1-22). Always 0
  /// for non-PDF pages.
  final int page;

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

  double _scale = 1.0;
  bool _showScaleOverlay = false;
  Timer? _scaleOverlayTimer;

  void _onTransformChanged() {
    final matrix = _transform.value;
    final scale = matrix.getMaxScaleOnAxis();
    if ((scale - _scale).abs() > 0.01) {
      setState(() {
        _scale = scale;
        _showScaleOverlay = true;
      });
      _scaleOverlayTimer?.cancel();
      _scaleOverlayTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            _showScaleOverlay = false;
          });
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _strokes = List.of(widget.initialStrokes);
    _transform.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    _scaleOverlayTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AnnotationCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset only when the stroke content actually changed, not just the list
    // instance. The editor builds a fresh filtered list every rebuild (R1-22);
    // without the content check every setState would wipe the in-progress
    // stroke and the undo/redo stacks.
    if (!identical(oldWidget.initialStrokes, widget.initialStrokes) &&
        !_sameStrokeList(oldWidget.initialStrokes, widget.initialStrokes)) {

      _strokes = List.of(widget.initialStrokes);
      _undo.clear();
      _redo.clear();
    }
  }

  /// True when both lists hold the same [Stroke] instances in the same order.
  static bool _sameStrokeList(List<Stroke> a, List<Stroke> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// GestureDetector is the direct child of InteractiveViewer, so
  /// `localPosition` is already in canvas space — no inverse transform needed.
  Offset _canvasPoint(Offset local) => local;

  void _beginStroke(Offset local) {
    HapticFeedback.lightImpact();
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
    HapticFeedback.lightImpact();
    final tool = widget.tool;
    if (tool == StrokeTool.eraser) {
      _erase(_points!);
    } else if (tool == StrokeTool.pen || tool == StrokeTool.highlighter) {
      _commit([
        Stroke(
          id: _strokeId(),
          tool: tool,
          color: widget.color,
          width: widget.width * (1 + pressure),
          points: List.of(_points!),
          page: widget.page,
        )
      ]);
    } else if (tool == StrokeTool.rect ||
        tool == StrokeTool.line ||
        tool == StrokeTool.arrow ||
        tool == StrokeTool.ellipse) {
      _commit([
        Stroke(
          id: _strokeId(),
          tool: tool,
          color: widget.color,
          width: widget.width,
          filled: false,
          start: _dragStart,
          end: _points!.last,
          page: widget.page,
        )
      ]);
    }
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
    HapticFeedback.lightImpact();
    _redo.add(List.of(_strokes));
    _strokes = _undo.removeLast();
    setState(() {});
    widget.onChanged?.call(_strokes);
  }

  void redo() {
    if (_redo.isEmpty) return;
    HapticFeedback.lightImpact();
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

  String _strokeId() => newId();

  void _zoomAt(Offset focal, double scale) {
    final m = _transform.value.clone()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
    _transform.value = m;
  }

  void zoomIn() => _zoomAt(_viewportCenter(), 1.2);
  void zoomOut() => _zoomAt(_viewportCenter(), 1 / 1.2);
  void fit() => _transform.value = Matrix4.identity();

  /// Focal point at the center of the visible viewport, in canvas space.
  Offset _viewportCenter() {
    final size = context.size;
    if (size == null) return Offset.zero;
    return _transform.toScene(size.center(Offset.zero));
  }

  @override
  Widget build(BuildContext context) {
    final canvasColor = Theme.of(context).scaffoldBackgroundColor;
    return ClipRect(
      child: LayoutBuilder(builder: (context, constraints) {
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
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
                        template: widget.template,
                        palette: PaperPalette.of(
                            themeModeOf(Theme.of(context).colorScheme)),
                        canvasColor: canvasColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_showScaleOverlay)
              Positioned(
                top: 16,
                right: 16,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(_scale),
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 200),
                  builder: (context, val, child) {
                    return Opacity(
                      opacity: val,
                      child: Card(
                        color: Colors.black.withAlpha(160),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            '${(_scale * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
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
        page: widget.page,
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
        page: widget.page,
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
                      page: widget.page,
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
    required this.template,
    required this.palette,
    required this.canvasColor,
  });

  final List<Stroke> strokes;
  final Stroke? inProgress;
  final ui.Image? backgroundImage;
  final String? template;
  final PaperPalette palette;
  final Color canvasColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = canvasColor,
    );

    if (template != null) {
      _paintTemplate(canvas, size);
    }

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

    // Draw active lagging pen tip-dot (E1-6)
    if (inProgress != null && inProgress!.points.isNotEmpty) {
      final tipPaint = Paint()
        ..color = inProgress!.color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(inProgress!.points.last, inProgress!.width * 0.75, tipPaint);
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
        if (s.points.length < 3) {
          final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
          for (final p in s.points.skip(1)) {
            path.lineTo(p.dx, p.dy);
          }
          canvas.drawPath(path, paint);
        } else {
          final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
          for (int i = 1; i < s.points.length - 1; i++) {
            final p0 = s.points[i];
            final p1 = s.points[i + 1];
            final xc = (p0.dx + p1.dx) / 2;
            final yc = (p0.dy + p1.dy) / 2;
            path.quadraticBezierTo(p0.dx, p0.dy, xc, yc);
          }
          path.lineTo(s.points.last.dx, s.points.last.dy);
          canvas.drawPath(path, paint);
        }
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

  void _paintTemplate(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = palette.text.withValues(alpha: 0.08)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    switch (template) {
      case 'lined':
        const spacing = 40.0;
        final lines = (size.height / spacing).floor();
        for (var i = 1; i <= lines; i++) {
          final y = i * spacing;
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        break;
      case 'grid':
        const spacing = 40.0;
        final rows = (size.height / spacing).floor();
        final cols = (size.width / spacing).floor();
        for (var i = 1; i <= rows; i++) {
          final y = i * spacing;
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        for (var j = 1; j <= cols; j++) {
          final x = j * spacing;
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        break;
      case 'dots':
        const spacing = 40.0;
        final rows = (size.height / spacing).floor();
        final cols = (size.width / spacing).floor();
        final dotPaint = Paint()
          ..color = palette.text.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill;
        for (var i = 1; i < rows; i++) {
          for (var j = 1; j < cols; j++) {
            canvas.drawCircle(Offset(j * spacing, i * spacing), 1.5, dotPaint);
          }
        }
        break;
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) =>
      old.strokes != strokes ||
      old.inProgress != inProgress ||
      old.backgroundImage != backgroundImage ||
      old.template != template ||
      old.palette != palette ||
      old.canvasColor != canvasColor;
}

