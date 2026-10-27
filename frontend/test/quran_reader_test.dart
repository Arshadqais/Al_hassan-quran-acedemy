import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/quran_reader.dart';

// Synthetic fixture content only; no scripture is generated in tests.
void main() {
  testWidgets(
    'All 30 paras are selectable and source text is rendered unchanged',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requested = <String>[];
      Future<dynamic> fetch(String path) async {
        requested.add(path);
        if (path == '/quran/surahs') {
          return List.generate(
            114,
            (i) => {'english_name': 'Test chapter ${i + 1}'},
          );
        }
        return {
          'verses': [
            {
              'number': 1,
              'text': 'UNCHANGED TEST FIXTURE',
              'surah': 1,
              'surah_english': 'Test chapter',
              'ayah': 1,
              'juz': 1,
            },
          ],
        };
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: QuranReader(fetch: fetch),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('UNCHANGED TEST FIXTURE'), findsOneWidget);
      final dropdown = tester.widget<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>),
      );
      // Open the real selection menu; every para has a selectable entry.
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Para 30'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Para 30').last);
      await tester.pumpAndSettle();
      expect(requested, contains('/quran/juz/30'));
      expect(dropdown.onChanged, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'A provider failure has a retry action and no invented Quran text',
    (tester) async {
      var failed = true;
      Future<dynamic> fetch(String path) async {
        if (failed) throw Exception('Provider unavailable');
        if (path == '/quran/surahs') return <dynamic>[];
        return {'verses': <dynamic>[]};
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: QuranReader(fetch: fetch)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Provider unavailable'), findsOneWidget);
      failed = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Para 1 · 0 ayahs'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
