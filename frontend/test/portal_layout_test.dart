import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/live_portal.dart';

void main() {
  for (final role in ['admin', 'teacher', 'student', 'parent']) {
    testWidgets('$role mobile portal navigation and saved record layouts', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final user = {
        'id': 1,
        'name': 'Test $role',
        'role': role,
        'email': '$role@example.test',
      };
      final student = {
        'id': 2,
        'name': 'Test Learner',
        'role': 'student',
        'email': 'student@example.test',
        'level': 'Level 1',
      };
      final start = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String();
      final api = AcademyApi(
        'https://academy.example',
        client: MockClient((request) async {
          final path = request.url.path;
          dynamic data = [];
          if (path.endsWith('/auth/login')) {
            data = {'user': user, 'token': 'layout-test-session'};
          } else if (path.endsWith('/admin/reports')) {
            data = {'students': 1, 'teachers': 1, 'classes': 1};
          } else if (path.endsWith('/users')) {
            data = [user, if (role != 'student') student];
          } else if (path.endsWith('/classes')) {
            data = [
              {
                'id': 1,
                'title': 'Quran Recitation',
                'teacher': 'Test Teacher',
                'category': 'Individual',
                'duration': 30,
                'starts_at': start,
              },
            ];
          } else if (path.endsWith('/attendance')) {
            data = [
              {'session_id': 1, 'student_id': 2, 'present': true},
            ];
          } else if (path.endsWith('/progress')) {
            data = [
              {'surah': 'Al-Fatiha', 'percent': 65, 'notes': 'Practice daily.'},
            ];
          } else if (path.endsWith('/homework')) {
            data = [
              {
                'id': 1,
                'student_id': 2,
                'title': 'Review the lesson',
                'completed': false,
              },
            ];
          } else if (path.endsWith('/resources')) {
            data = [
              {
                'id': 1,
                'student_id': 2,
                'title': 'Tajweed rules',
                'content': 'Study note',
              },
            ];
          }
          return http.Response(jsonEncode(data), 200);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: LivePortal(api: api, realtime: false),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('login-email')),
        '$role@example.test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('login-password')),
        'layout-test-password',
      );
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Assalamu Alaikum,'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$role overview');
      for (final page in [
        'Classes',
        'Progress',
        'Attendance',
        'Resources',
        'Messages',
        'Account',
      ]) {
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        final item = find.descendant(
          of: find.byType(Drawer),
          matching: find.text(page),
        );
        await tester.scrollUntilVisible(
          item,
          160,
          scrollable: find
              .descendant(
                of: find.byType(Drawer),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(item);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$role $page');
        if (page == 'Classes') {
          expect(find.text('Quran Recitation'), findsOneWidget);
          await tester.tap(find.text('Past'));
          await tester.pumpAndSettle();
          expect(find.text('No past classes yet.'), findsOneWidget);
          await tester.tap(find.text('Upcoming'));
          await tester.pumpAndSettle();
          expect(find.text('Quran Recitation'), findsOneWidget);
        }
        if (page == 'Attendance') {
          expect(find.text('Present'), findsOneWidget);
          await tester.tap(find.byTooltip('Previous month'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        if (page == 'Resources') {
          expect(find.text('Tajweed rules'), findsOneWidget);
          await tester.enterText(find.byType(TextField), 'missing');
          await tester.pumpAndSettle();
          expect(find.text('Tajweed rules'), findsNothing);
        }
      }
    });
  }
}
