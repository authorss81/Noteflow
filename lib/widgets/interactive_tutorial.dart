import 'package:flutter/material.dart';

class TutorialStep {
  final String title;
  final String description;
  final GlobalKey? anchorKey;
  final VoidCallback? onStepShow;

  const TutorialStep({
    required this.title,
    required this.description,
    this.anchorKey,
    this.onStepShow,
  });
}

class InteractiveTutorial extends StatefulWidget {
  const InteractiveTutorial({
    super.key,
    required this.steps,
    required this.onComplete,
    required this.onSkip,
  });

  final List<TutorialStep> steps;
  final VoidCallback onComplete;
  final VoidCallback onSkip;

  @override
  State<InteractiveTutorial> createState() => _InteractiveTutorialState();
}

class _InteractiveTutorialState extends State<InteractiveTutorial> {
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _triggerShow();
  }

  void _triggerShow() {
    if (_currentStep >= 0 && _currentStep < widget.steps.length) {
      widget.steps[_currentStep].onStepShow?.call();
    }
  }

  void _next() {
    if (_currentStep < widget.steps.length - 1) {
      setState(() {
        _currentStep++;
      });
      _triggerShow();
    } else {
      widget.onComplete();
    }
  }

  void _prev() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
      _triggerShow();
    }
  }

  Rect? _getTargetRect(GlobalKey? key) {
    if (key == null) return null;
    final context = key.currentContext;
    if (context == null) return null;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    return offset & size;
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_currentStep];
    final targetRect = _getTargetRect(step.anchorKey);
    final size = MediaQuery.of(context).size;
    final scheme = Theme.of(context).colorScheme;

    Widget card = Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tips_and_updates, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    step.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              step.description,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: widget.onSkip,
                  child: const Text('Skip'),
                ),
                Row(
                  children: [
                    if (_currentStep > 0)
                      TextButton(
                        onPressed: _prev,
                        child: const Text('Prev'),
                      ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _next,
                      child: Text(_currentStep == widget.steps.length - 1 ? 'Finish' : 'Next'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // Position card dynamically based on highlighted rect
    double? cardTop;
    double? cardLeft;

    if (targetRect == null) {
      // Center of screen
      cardTop = (size.height - 200) / 2;
      cardLeft = (size.width - 300) / 2;
    } else {
      final midY = targetRect.top + targetRect.height / 2;
      if (midY > size.height / 2) {
        // Place card above the target
        cardTop = targetRect.top - 200;
        if (cardTop < 20) cardTop = 20;
      } else {
        // Place card below the target
        cardTop = targetRect.bottom + 20;
      }

      // Horizontal alignment: try to center on target but keep within bounds
      final targetMidX = targetRect.left + targetRect.width / 2;
      cardLeft = targetMidX - 150;
      if (cardLeft < 16) cardLeft = 16;
      if (cardLeft + 300 > size.width - 16) {
        cardLeft = size.width - 316;
      }
    }

    return Stack(
      children: [
        // Backdrop with hole cutout
        Positioned.fill(
          child: CustomPaint(
            painter: _TutorialHolePainter(targetRect),
          ),
        ),
        // Description Card
        Positioned(
          top: cardTop,
          left: cardLeft,
          child: card,
        ),
      ],
    );
  }
}

class _TutorialHolePainter extends CustomPainter {
  final Rect? targetRect;
  _TutorialHolePainter(this.targetRect);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withAlpha(180);
    if (targetRect == null) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
      return;
    }

    final fullPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          targetRect!.inflate(8),
          const Radius.circular(12),
        ),
      );

    final combinedPath = Path.combine(PathOperation.difference, fullPath, cutoutPath);
    canvas.drawPath(combinedPath, paint);
  }

  @override
  bool shouldRepaint(covariant _TutorialHolePainter oldDelegate) =>
      oldDelegate.targetRect != targetRect;
}
