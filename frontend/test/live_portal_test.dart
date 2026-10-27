import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/live_portal.dart';
import 'package:frontend/main.dart';

void main() {
  test('Debug defaults to the local API for plain flutter run', () {
    expect(academyApiBaseUrl, 'http://127.0.0.1:8000');
  });
  test(
    'API rejects unconfigured servers and expires tokens on unauthorized responses',
    () async {
      final missing = AcademyApi('');
      expect(missing.configured, isFalse);
      await expectLater(missing.call('/users'), throwsA(isA<ApiFailure>()));
      missing.close();
      final api = AcademyApi(
        'https://academy.example',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer test-session');
          return http.Response('{"detail":"Expired"}', 401);
        }),
      );
      api.token = 'test-session';
      await expectLater(api.call('/users'), throwsA(isA<ApiFailure>()));
      expect(api.token, isNull);
      api.close();
    },
  );
  testWidgets('Unconfigured live portal explains status without a fake login', (
    tester,
  ) async {
    final api = AcademyApi('');
    await tester.pumpWidget(
      MaterialApp(home: LivePortal(api: api, realtime: false)),
    );
    expect(find.textContaining('has not been connected'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });
  testWidgets('Live student signs in, sees authorized records, and signs out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const user = {
      'id': 3,
      'name': 'Real Test Student',
      'role': 'student',
      'email': 'learner@example.test',
    };
    final requests = <String>[];
    final api = AcademyApi(
      'https://academy.example',
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path == '/api/auth/login') {
          expect(jsonDecode(request.body)['email'], 'learner@example.test');
          return http.Response(
            jsonEncode({
              'user': user,
              'token': 'server-session',
              'expires_in': 28800,
            }),
            200,
          );
        }
        expect(request.headers['Authorization'], 'Bearer server-session');
        if (request.url.path == '/api/auth/logout') {
          return http.Response('', 204);
        }
        if (request.url.path == '/api/users') {
          return http.Response(jsonEncode([user]), 200);
        }
        return http.Response('[]', 200);
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
      'learner@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-password')),
      'Test-password-123!',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Assalamu Alaikum, Real Test Student'), findsOneWidget);
    expect(find.text('People'), findsNothing);
    expect(find.text('Assignments'), findsNothing);
    expect(find.text('Reports'), findsNothing);
    expect(find.textContaining('No classes scheduled'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(api.token, isNull);
    expect(requests, contains('POST /api/auth/logout'));
  });
  testWidgets('Academy sign in is reachable from the public website', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const AcademyApp());
    await tester.tap(find.text('Academy sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
