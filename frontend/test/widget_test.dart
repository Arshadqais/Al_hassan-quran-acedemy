import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

Future<void> openPortal(
  WidgetTester tester,
  String role, {
  bool mobile = false,
}) async {
  tester.view.physicalSize = mobile
      ? const Size(390, 844)
      : const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(const AcademyApp());
  await tester.tap(find.text(mobile ? 'Explore' : 'Explore the academy'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.text(role == 'Admin' ? 'Admin / Principal' : role).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Landing and all four portals render without exceptions', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final role in ['Student', 'Teacher', 'Admin', 'Parent']) {
      await tester.pumpWidget(Container());
      await openPortal(tester, role);
      expect(find.textContaining('Assalamu Alaikum,'), findsOneWidget);
      expect(find.textContaining('Fictional records.'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$role desktop');
    }
  });
  testWidgets('Mobile dashboard and drawer pages do not overflow', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openPortal(tester, 'Student', mobile: true);
    expect(tester.takeException(), isNull);
    for (final page in [
      'Quran progress',
      'Attendance',
      'Resources',
      'Homework',
      'Settings',
    ]) {
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      final item = find.descendant(
        of: find.byType(Drawer),
        matching: find.text(page),
      );
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: page);
    }
  });
  testWidgets('Admin adds a student and can search their record', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openPortal(tester, 'Admin');
    await tester.tap(find.text('Students').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add student'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'Test Learner');
    await tester.enterText(
      find.byType(TextField).at(2),
      'learner@example.test',
    );
    await tester.tap(find.text('Add record'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Test Learner');
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == 'Test Learner'),
      findsOneWidget,
    );
    expect(find.text('Ali Hassan'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Student can complete homework and send a local demo message', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openPortal(tester, 'Student');
    await tester.tap(find.text('Homework').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('Completed in this demo'), findsOneWidget);
    await tester.tap(find.text('Messages').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Thank you for the lesson.');
    await tester.tap(find.byTooltip('Add demo message'));
    await tester.pumpAndSettle();
    expect(find.text('Thank you for the lesson.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Teacher can update Quran progress and attendance', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openPortal(tester, 'Teacher');
    await tester.tap(find.text('Quran progress').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Update progress').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Slider));
    await tester.tap(find.text('Save progress'));
    await tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
    await tester.tap(find.text('Attendance').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('2 / 4 present'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Parent switching children shows distinct progress', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openPortal(tester, 'Parent');
    await tester.tap(find.text('My children').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Fatima Khan'));
    await tester.pumpAndSettle();
    expect(find.text('40% complete · Level 2'), findsOneWidget);
    expect(find.textContaining('Fatima is growing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
