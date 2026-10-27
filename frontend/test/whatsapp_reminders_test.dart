import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/whatsapp_reminders.dart';

void main() {
  testWidgets(
    'User must supply international number to opt in and can opt out',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saves = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WhatsAppReminderSettings(
                fetch: (_) async => {'phone': '', 'consent': false},
                save: (path, body) async {
                  expect(path, '/auth/reminder-contact');
                  saves.add(body);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.ensureVisible(find.text('Save reminder preference'));
      await tester.tap(find.text('Save reminder preference'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a valid international phone number.'),
        findsOneWidget,
      );
      expect(saves, isEmpty);
      await tester.enterText(find.byType(TextFormField), '+923001234567');
      await tester.ensureVisible(find.text('Save reminder preference'));
      await tester.tap(find.text('Save reminder preference'));
      await tester.pumpAndSettle();
      expect(saves.single, {'phone': '+923001234567', 'consent': true});
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.ensureVisible(find.text('Save reminder preference'));
      await tester.tap(find.text('Save reminder preference'));
      await tester.pumpAndSettle();
      expect(saves.last['consent'], false);
      expect(find.textContaining('You have opted out'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Admin distinguishes accepted from delivered and sees masked phone',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReminderDelivery(
                fetch: (_) async => {
                  'configured': true,
                  'receipts_configured': false,
                  'minutes': 10,
                  'deliveries': [
                    {
                      'class_title': 'Quran lesson',
                      'recipient': 'Teacher',
                      'phone': '••••4567',
                      'state': 'accepted',
                      'error_code': '',
                    },
                    {
                      'class_title': 'Quran lesson',
                      'recipient': 'Parent',
                      'phone': '••••9876',
                      'state': 'delivered',
                      'error_code': '',
                    },
                  ],
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Accepted by WhatsApp'), findsOneWidget);
      expect(find.text('Delivered'), findsOneWidget);
      expect(
        find.textContaining('Accepted does not mean delivered'),
        findsOneWidget,
      );
      expect(find.text('Teacher · ••••4567'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
