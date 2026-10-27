import 'dart:convert';
import 'package:flutter/material.dart';

const annotationTopic = 'academy.screen-rectangles.v1';

/// Coordinates are relative to the video, not the browser window. This keeps
/// highlights aligned across differently sized teacher and student views.
class AnnotationSnapshot {
  final String track;
  final int revision;
  final List<Rect> rectangles;
  const AnnotationSnapshot(this.track, this.revision, this.rectangles);
  List<int> encode() => utf8.encode(
    jsonEncode({
      'track': track,
      'revision': revision,
      'rectangles': rectangles
          .map((r) => [r.left, r.top, r.right, r.bottom])
          .toList(),
    }),
  );
  static AnnotationSnapshot? decode(List<int> bytes) {
    if (bytes.length > 8192) return null;
    try {
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map ||
          data['track'] is! String ||
          (data['track'] as String).length > 128 ||
          data['revision'] is! int ||
          data['revision'] < 0 ||
          data['rectangles'] is! List ||
          (data['rectangles'] as List).length > 50) {
        return null;
      }
      final rectangles = <Rect>[];
      for (final raw in data['rectangles']) {
        if (raw is! List ||
            raw.length != 4 ||
            raw.any((v) => v is! num || !v.isFinite || v < 0 || v > 1)) {
          return null;
        }
        final r = Rect.fromLTRB(
          (raw[0] as num).toDouble(),
          (raw[1] as num).toDouble(),
          (raw[2] as num).toDouble(),
          (raw[3] as num).toDouble(),
        );
        if (r.width <= 0 || r.height <= 0) return null;
        rectangles.add(r);
      }
      return AnnotationSnapshot(data['track'], data['revision'], rectangles);
    } catch (_) {
      return null;
    }
  }
}

class ScreenAnnotationCanvas extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final List<Rect> rectangles;
  final ValueChanged<List<Rect>> onChanged;
  const ScreenAnnotationCanvas({
    super.key,
    required this.child,
    required this.enabled,
    required this.rectangles,
    required this.onChanged,
  });
  @override
  State<ScreenAnnotationCanvas> createState() => _ScreenAnnotationCanvasState();
}

class _ScreenAnnotationCanvasState extends State<ScreenAnnotationCanvas> {
  Offset? start, end;
  @override
  void didUpdateWidget(covariant ScreenAnnotationCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      start = null;
      end = null;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      Offset relative(Offset point) => Offset(
        (point.dx / c.maxWidth).clamp(0, 1),
        (point.dy / c.maxHeight).clamp(0, 1),
      );
      final draft = start == null || end == null
          ? null
          : Rect.fromPoints(start!, end!);
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Semantics(
            container: true,
            label: 'Screen highlights: ${widget.rectangles.length}',
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RectanglePainter([...widget.rectangles, ?draft]),
              ),
            ),
          ),
          if (widget.enabled)
            Semantics(
              container: true,
              label: 'Shared screen annotation area',
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                child: GestureDetector(
                  key: const ValueKey('screen-rectangle-surface'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => setState(() {
                    start = relative(d.localPosition);
                    end = start;
                  }),
                  onPanUpdate: (d) =>
                      setState(() => end = relative(d.localPosition)),
                  onPanCancel: () => setState(() {
                    start = null;
                    end = null;
                  }),
                  onPanEnd: (_) {
                    if (start != null && end != null) {
                      final r = Rect.fromPoints(start!, end!);
                      if (r.width > .003 && r.height > .003) {
                        widget.onChanged([...widget.rectangles.take(49), r]);
                      }
                    }
                    setState(() {
                      start = null;
                      end = null;
                    });
                  },
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _RectanglePainter extends CustomPainter {
  final List<Rect> rectangles;
  _RectanglePainter(this.rectangles);
  @override
  void paint(Canvas canvas, Size size) {
    for (final r in rectangles) {
      final rect = Rect.fromLTRB(
        r.left * size.width,
        r.top * size.height,
        r.right * size.width,
        r.bottom * size.height,
      );
      canvas.drawRect(rect, Paint()..color = const Color(0x33FFCC43));
      canvas.drawRect(
        rect,
        Paint()
          ..color = const Color(0xFFFFCC43)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RectanglePainter oldDelegate) => true;
}
