import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blackbox/src/overlay/panels/qa/qa_annotation_layer.dart';

void main() {
  group('QaAnnotationLayer', () {
    testWidgets('respects stroke point limit of 2000',
        (WidgetTester tester) async {
      final strokes = <AnnotationStroke>[];
      int repaintVersion = 0;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: QaAnnotationLayer(
            isInteractive: true,
            currentTool: AnnotationTool.freehand,
            strokes: strokes,
            repaintVersion: repaintVersion,
            onStrokeComplete: (stroke) {
              strokes.add(stroke);
            },
            onRepaintRequested: () {},
          ),
        ),
      ));

      // Draw a line with many small movements
      final gesture = await tester.startGesture(const Offset(10, 10));
      for (int i = 0; i < 2100; i++) {
        // Move by enough distance to pass the distance-squared threshold (9.0 => >3 pixels)
        await gesture.moveBy(const Offset(4, 4));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      expect(strokes, hasLength(1));
      // Max points should be capped at 2000
      expect(strokes.first.points.length, lessThanOrEqualTo(2000));
    });

    testWidgets('does not interact when isInteractive is false',
        (WidgetTester tester) async {
      final strokes = <AnnotationStroke>[];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: QaAnnotationLayer(
            isInteractive: false,
            currentTool: AnnotationTool.freehand,
            strokes: strokes,
            repaintVersion: 0,
            onStrokeComplete: (stroke) {
              strokes.add(stroke);
            },
            onRepaintRequested: () {},
          ),
        ),
      ));

      final gesture = await tester.startGesture(const Offset(10, 10));
      await gesture.moveBy(const Offset(10, 10));
      await gesture.up();
      await tester.pump();

      expect(strokes, isEmpty);
    });

    testWidgets('Move tool translates stroke and preserves z-order',
        (WidgetTester tester) async {
      final stroke1 = AnnotationStroke(
        tool: AnnotationTool.circle,
        color: Colors.red,
        points: [const Offset(100, 100), const Offset(150, 100)], // radius 50
      );
      final stroke2 = AnnotationStroke(
        tool: AnnotationTool.rectangle,
        color: Colors.orange,
        points: [const Offset(90, 90), const Offset(160, 160)],
      );

      final strokes = <AnnotationStroke>[stroke1, stroke2]; // stroke2 is on top

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: QaAnnotationLayer(
            isInteractive: true,
            currentTool: AnnotationTool.move,
            strokes: strokes,
            repaintVersion: 0,
            onStrokeComplete: (_) {},
            onRepaintRequested: () {},
          ),
        ),
      ));

      // Drag inside overlapping area (120, 120)
      // Should hit topmost (stroke2)
      final gesture = await tester.startGesture(const Offset(120, 120));
      await gesture.moveBy(const Offset(20, 30));
      await gesture.up();
      await tester.pump();

      // Ensure no new stroke was created
      expect(strokes.length, 2);

      // Ensure stroke2 was moved by (20, 30)
      expect(strokes[1].points.first, const Offset(110, 120));
      expect(strokes[1].points.last, const Offset(180, 190));

      // Ensure stroke1 was untouched
      expect(strokes[0].points.first, const Offset(100, 100));
    });

    testWidgets('Move tool empty space tap does nothing',
        (WidgetTester tester) async {
      final strokes = <AnnotationStroke>[
        AnnotationStroke(
          tool: AnnotationTool.circle,
          color: Colors.red,
          points: [const Offset(100, 100), const Offset(150, 100)],
        )
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: QaAnnotationLayer(
            isInteractive: true,
            currentTool: AnnotationTool.move,
            strokes: strokes,
            repaintVersion: 0,
            onStrokeComplete: (_) {},
            onRepaintRequested: () {},
          ),
        ),
      ));

      // Drag in empty space (300, 300)
      final gesture = await tester.startGesture(const Offset(300, 300));
      await gesture.moveBy(const Offset(20, 30));
      await gesture.up();
      await tester.pump();

      // Stroke untouched
      expect(strokes[0].points.first, const Offset(100, 100));
    });
  });
}
