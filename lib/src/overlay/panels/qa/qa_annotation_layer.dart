import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../widgets/blackbox_colors.dart';

enum AnnotationTool { freehand, line, rectangle, circle, move }

class AnnotationStroke {
  AnnotationStroke({
    required this.tool,
    required this.color,
    required this.points,
  });

  final AnnotationTool tool;
  final Color color;
  final List<Offset> points;
}

class QaAnnotationLayer extends StatefulWidget {
  const QaAnnotationLayer({
    super.key,
    required this.strokes,
    required this.currentTool,
    required this.isInteractive,
    required this.repaintVersion,
    required this.onStrokeComplete,
    required this.onRepaintRequested,
  });

  final List<AnnotationStroke> strokes;
  final AnnotationTool currentTool;
  final bool isInteractive;
  final int repaintVersion;
  final ValueChanged<AnnotationStroke> onStrokeComplete;
  final VoidCallback onRepaintRequested;

  @override
  State<QaAnnotationLayer> createState() => _QaAnnotationLayerState();
}

class _QaAnnotationLayerState extends State<QaAnnotationLayer> {
  final ValueNotifier<int> _canvasRepaintNotifier = ValueNotifier<int>(0);
  AnnotationStroke? _activeStroke;

  int? _selectedStrokeIndex;

  // For scaling
  List<Offset>? _selectedOriginalPoints;
  Offset? _centroid;
  int _lastPointerCount = 0;

  @override
  void didUpdateWidget(covariant QaAnnotationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.repaintVersion != oldWidget.repaintVersion ||
        widget.strokes != oldWidget.strokes) {
      _canvasRepaintNotifier.value++;
    }
  }

  @override
  void dispose() {
    _canvasRepaintNotifier.dispose();
    super.dispose();
  }

  bool _hitTestStroke(AnnotationStroke stroke, Offset touch) {
    switch (stroke.tool) {
      case AnnotationTool.freehand:
        for (final p in stroke.points) {
          if ((p - touch).distanceSquared < 400) return true; // 20px
        }
        return false;
      case AnnotationTool.line:
        if (stroke.points.length < 2) return false;
        return _distToSegment(touch, stroke.points.first, stroke.points.last) <
            20;
      case AnnotationTool.rectangle:
        if (stroke.points.length < 2) return false;
        final rect = Rect.fromPoints(stroke.points.first, stroke.points.last);
        return rect.contains(touch);
      case AnnotationTool.circle:
        if (stroke.points.length < 2) return false;
        final center = stroke.points.first;
        final radius = (stroke.points.last - center).distance;
        return (touch - center).distance <= radius;
      case AnnotationTool.move:
        return false;
    }
  }

  double _distToSegment(Offset p, Offset a, Offset b) {
    final l2 = (a - b).distanceSquared;
    if (l2 == 0) return (p - a).distance;
    var t =
        ((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2;
    t = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * (b.dx - a.dx), a.dy + t * (b.dy - a.dy));
    return (p - proj).distance;
  }

  Offset _calculateCentroid(List<Offset> points) {
    if (points.isEmpty) return Offset.zero;
    if (points.length == 1) return points.first;

    double minX = points.first.dx, maxX = points.first.dx;
    double minY = points.first.dy, maxY = points.first.dy;

    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Offset((minX + maxX) / 2, (minY + maxY) / 2);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _lastPointerCount = details.pointerCount;

    if (widget.currentTool == AnnotationTool.move) {
      _selectedStrokeIndex = null;
      _selectedOriginalPoints = null;
      _centroid = null;

      for (var i = widget.strokes.length - 1; i >= 0; i--) {
        if (_hitTestStroke(widget.strokes[i], details.localFocalPoint)) {
          _selectedStrokeIndex = i;
          final points = widget.strokes[i].points;
          if (points.isNotEmpty) {
            _selectedOriginalPoints = List.from(points);
            _centroid = _calculateCentroid(points);
          }
          break;
        }
      }
      return;
    }

    if (details.pointerCount > 1) return;

    _activeStroke = AnnotationStroke(
      tool: widget.currentTool,
      color: BlackBoxColors.error,
      points: [details.localFocalPoint],
    );
    _canvasRepaintNotifier.value++;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (widget.currentTool == AnnotationTool.move) {
      if (_selectedStrokeIndex != null &&
          _selectedOriginalPoints != null &&
          _centroid != null) {
        if (_selectedStrokeIndex! < 0 ||
            _selectedStrokeIndex! >= widget.strokes.length) {
          return;
        }
        final stroke = widget.strokes[_selectedStrokeIndex!];

        if (details.pointerCount != _lastPointerCount ||
            _selectedOriginalPoints!.length != stroke.points.length) {
          _selectedOriginalPoints = List.from(stroke.points);
          _centroid = _calculateCentroid(stroke.points);
          _lastPointerCount = details.pointerCount;
        }

        if (_selectedOriginalPoints!.length != stroke.points.length) return;

        final delta = details.focalPointDelta;
        _centroid = _centroid! + delta;

        for (int i = 0; i < stroke.points.length; i++) {
          _selectedOriginalPoints![i] += delta;
        }

        final scaleFactor = details.scale.clamp(0.25, 4.0);
        for (int i = 0; i < stroke.points.length; i++) {
          final p = _selectedOriginalPoints![i];
          stroke.points[i] = _centroid! + (p - _centroid!) * scaleFactor;
        }

        _canvasRepaintNotifier.value++;
      }
      return;
    }

    if (_activeStroke == null) return;
    if (details.pointerCount > 1) return;

    if (_activeStroke!.tool == AnnotationTool.freehand) {
      if (_activeStroke!.points.length >= 2000) return;
    }

    final lastPoint = _activeStroke!.points.last;
    final newPoint = details.localFocalPoint;
    if ((lastPoint - newPoint).distanceSquared > 4) {
      _activeStroke!.points.add(newPoint);
      _canvasRepaintNotifier.value++;
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (widget.currentTool == AnnotationTool.move) {
      _selectedStrokeIndex = null;
      _selectedOriginalPoints = null;
      _centroid = null;
      widget.onRepaintRequested();
      _canvasRepaintNotifier.value++;
      return;
    }

    if (_activeStroke == null) return;
    if (_activeStroke!.points.length > 1 ||
        _activeStroke!.tool != AnnotationTool.freehand) {
      widget.onStrokeComplete(_activeStroke!);
    }
    _activeStroke = null;
    _canvasRepaintNotifier.value++;
  }

  @override
  Widget build(BuildContext context) {
    final painter = CustomPaint(
      painter: _AnnotationPainter(
        repaint: _canvasRepaintNotifier,
        strokes: widget.strokes,
        getActiveStroke: () => _activeStroke,
      ),
      size: Size.infinite,
    );

    if (!widget.isInteractive) {
      return IgnorePointer(child: painter);
    }

    return GestureDetector(
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      onScaleEnd: _handleScaleEnd,
      behavior: HitTestBehavior.opaque,
      child: painter,
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  _AnnotationPainter({
    required super.repaint,
    required this.strokes,
    required this.getActiveStroke,
  });

  final List<AnnotationStroke> strokes;
  final AnnotationStroke? Function() getActiveStroke;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 4.0;

    for (final stroke in strokes) {
      _paintStroke(canvas, stroke, paint);
    }

    final active = getActiveStroke();
    if (active != null) {
      _paintStroke(canvas, active, paint);
    }
  }

  void _paintStroke(Canvas canvas, AnnotationStroke stroke, Paint paint) {
    if (stroke.points.isEmpty) return;
    paint.color = stroke.color;

    switch (stroke.tool) {
      case AnnotationTool.freehand:
        if (stroke.points.length == 1) {
          canvas.drawPoints(ui.PointMode.points, stroke.points, paint);
        } else {
          final path = Path()
            ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
          for (var i = 1; i < stroke.points.length; i++) {
            path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
          }
          canvas.drawPath(path, paint);
        }
        break;
      case AnnotationTool.line:
        if (stroke.points.length >= 2) {
          canvas.drawLine(stroke.points.first, stroke.points.last, paint);
        }
        break;
      case AnnotationTool.rectangle:
        if (stroke.points.length >= 2) {
          final rect = Rect.fromPoints(stroke.points.first, stroke.points.last);
          canvas.drawRect(rect, paint);
        }
        break;
      case AnnotationTool.circle:
        if (stroke.points.length >= 2) {
          final center = stroke.points.first;
          final radius = (stroke.points.last - center).distance;
          canvas.drawCircle(center, radius, paint);
        }
        break;
      case AnnotationTool.move:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) {
    return true;
  }
}
