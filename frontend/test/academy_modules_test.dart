import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/student_records.dart';
import 'package:frontend/recurring_schedule.dart';
import 'package:frontend/conversation_review.dart';
import 'package:frontend/screen_annotations.dart';

void main() {
  const students = [
    {'id': 3, 'name': 'Ali', 'level': 'Level 1'},
    {'id': 5, 'name': 'Fatima', 'level': 'Level 2'},
  ];
  testWidgets(
    'Parent selects a child and sees scoped attendance summary/chart',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final paths = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StudentRecords(
                students: students,
                initialStudentId: 5,
                fetch: (path) async {
                  paths.add(path);
                  final child = path.contains('/5/')
                      ? students[1]
                      : students[0];
                  return {
                    'student': child,
                    'timezone': 'Asia/Karachi',
                    'attendance': {
                      'present': 2,
                      'absent': 1,
                      'unrecorded': 1,
                      'rate': 66.7,
                    },
                    'months': [
                      {
                        'month': '2026-10',
                        'present': 2,
                        'absent': 1,
                        'unrecorded': 1,
                        'total': 4,
                      },
                    ],
                    'homework': {'completed': 1, 'total': 2},
                    'resources': 3,
                    'progress': [],
                    'lessons': [],
                  };
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(paths, ['/students/5/summary']);
      expect(find.text('66.7%'), findsOneWidget);
      expect(find.byType(AttendanceChart), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ali').last);
      await tester.pumpAndSettle();
      expect(paths.last, '/students/3/summary');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Teacher saves one weekly rule with timezone and weekdays', (
    tester,
  ) async {
    final saved = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecurringSchedules(
              fetch: (_) async => [],
              save: (path, body) async {
                expect(path, '/schedules');
                saved.add(body);
              },
              students: students,
              teachers: const [
                {'id': 2, 'name': 'Teacher'},
              ],
              editor: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set weekly schedule'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Class title'),
      'Evening Quran',
    );
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teacher').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(CheckboxListTile, 'Ali'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Ali'));
    await tester.tap(find.text('Save repeating schedule'));
    await tester.pumpAndSettle();
    expect(saved.single['weekdays'], [0, 1, 2, 3, 4]);
    expect(saved.single['timezone'], 'Asia/Karachi');
    expect(saved.single['student_ids'], [3]);
    expect(saved.single.containsKey('starts_at'), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Admin opens read-only review and sees sender attribution', (
    tester,
  ) async {
    final paths = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ConversationReview(
              fetch: (path) async {
                paths.add(path);
                if (path.contains('?offset=')) {
                  return [
                    {
                      'first': {'id': 2, 'name': 'Teacher', 'role': 'teacher'},
                      'second': {'id': 3, 'name': 'Ali', 'role': 'student'},
                      'count': 1,
                    },
                  ];
                }
                return [
                  {
                    'id': 1,
                    'sender_id': 2,
                    'text': 'Revise your lesson',
                    'created_at': '2026-10-27T12:00:00',
                  },
                ];
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teacher ↔ Ali'));
    await tester.pumpAndSettle();
    expect(paths.last, '/admin/conversations/2/3');
    expect(find.text('Revise your lesson'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test(
    'Screen rectangle codec validates bounds and never accepts malformed packets',
    () {
      const snapshot = AnnotationSnapshot('TR_test', 1, [
        Rect.fromLTRB(.1, .2, .8, .4),
      ]);
      expect(
        AnnotationSnapshot.decode(snapshot.encode())!.rectangles,
        snapshot.rectangles,
      );
      for (final payload in [
        {
          'track': 'x',
          'revision': 1,
          'rectangles': [
            [0, 0, 2, 1],
          ],
        },
        {
          'track': 'x',
          'revision': 1,
          'rectangles': [
            [.8, 0, .1, 1],
          ],
        },
        {'track': 'x', 'revision': -1, 'rectangles': []},
        {
          'track': 'x',
          'revision': 1,
          'rectangles': List.filled(51, [0, 0, 1, 1]),
        },
      ]) {
        expect(
          AnnotationSnapshot.decode(utf8.encode(jsonEncode(payload))),
          isNull,
        );
      }
      expect(AnnotationSnapshot.decode(List.filled(9000, 0)), isNull);
    },
  );
  testWidgets(
    'Teacher drags a normalized rectangle; student view cannot draw',
    (tester) async {
      List<Rect> rects = [];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              height: 200,
              child: ScreenAnnotationCanvas(
                enabled: true,
                rectangles: const [],
                onChanged: (r) => rects = r,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );
      final surface = find.byKey(const ValueKey('screen-rectangle-surface'));
      final origin = tester.getTopLeft(surface);
      final gesture = await tester.startGesture(origin + const Offset(40, 40));
      await gesture.moveTo(origin + const Offset(320, 120));
      await gesture.up();
      await tester.pump();
      expect(rects, hasLength(1));
      expect(rects.single.left, closeTo(.1, .01));
      expect(rects.single.right, closeTo(.8, .01));
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 200,
            height: 100,
            child: ScreenAnnotationCanvas(
              enabled: false,
              rectangles: rects,
              onChanged: (_) => fail('Student drew a highlight'),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('screen-rectangle-surface')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
