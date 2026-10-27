import 'package:flutter/material.dart';
import 'academy_design.dart';

class WhatsAppReminderSettings extends StatefulWidget {
  final Future<dynamic> Function(String) fetch;
  final Future<void> Function(String, Map<String, dynamic>) save;
  const WhatsAppReminderSettings({
    super.key,
    required this.fetch,
    required this.save,
  });
  @override
  State<WhatsAppReminderSettings> createState() =>
      _WhatsAppReminderSettingsState();
}

class _WhatsAppReminderSettingsState extends State<WhatsAppReminderSettings> {
  final phone = TextEditingController();
  final form = GlobalKey<FormState>();
  bool loading = true, saving = false, consent = false;
  String error = '', status = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final data = await widget.fetch('/auth/reminder-contact');
      if (mounted) {
        setState(() {
          phone.text = data['phone'] as String;
          consent = data['consent'] as bool;
          error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'WhatsApp class reminders',
        style: TextStyle(
          fontFamily: 'CormorantGaramond',
          fontSize: 30,
          color: academyEmerald,
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Receive a message before your class starts. Teachers and enrolled students can opt in; linked parents receive their children’s reminders. Your phone number is not shown to other users.',
        style: TextStyle(fontSize: 12, height: 1.8),
      ),
      const SizedBox(height: 24),
      if (loading)
        const Center(child: CircularProgressIndicator())
      else
        Card(
          color: Colors.white,
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Your WhatsApp number',
                      hintText: '+923001234567',
                      helperText: 'Include + and your country code; no spaces.',
                    ),
                    validator: (v) =>
                        ((v ?? '').trim().isEmpty && !consent) ||
                            RegExp(
                              r'^\+[1-9]\d{7,14}$',
                            ).hasMatch((v ?? '').trim())
                        ? null
                        : 'Enter a valid international phone number.',
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: consent,
                    title: const Text(
                      'I agree to receive class reminders on this WhatsApp number.',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: const Text(
                      'Use your own number or one you have permission to use. Uncheck this option and save to stop future reminders.',
                      style: TextStyle(fontSize: 11),
                    ),
                    onChanged: saving
                        ? null
                        : (v) => setState(() => consent = v ?? false),
                  ),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        error,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  if (status.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        status,
                        style: const TextStyle(color: academyEmerald),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            if (!form.currentState!.validate()) return;
                            setState(() {
                              saving = true;
                              error = '';
                              status = '';
                            });
                            try {
                              await widget.save('/auth/reminder-contact', {
                                'phone': phone.text.trim(),
                                'consent': consent,
                              });
                              if (mounted) {
                                setState(
                                  () => status = consent
                                      ? 'Reminder preference saved. Messages require the academy’s WhatsApp service to be connected.'
                                      : 'You have opted out of future WhatsApp reminders.',
                                );
                              }
                            } catch (e) {
                              if (mounted) setState(() => error = e.toString());
                            } finally {
                              if (mounted) setState(() => saving = false);
                            }
                          },
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: Text(
                      saving ? 'Saving…' : 'Save reminder preference',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

class ReminderDelivery extends StatefulWidget {
  final Future<dynamic> Function(String) fetch;
  const ReminderDelivery({super.key, required this.fetch});
  @override
  State<ReminderDelivery> createState() => _ReminderDeliveryState();
}

class _ReminderDeliveryState extends State<ReminderDelivery> {
  late Future<dynamic> data;
  @override
  void initState() {
    super.initState();
    data = widget.fetch('/admin/reminders');
  }

  static const labels = {
    'pending': 'Queued',
    'sending': 'Sending',
    'accepted': 'Accepted by WhatsApp',
    'sent': 'Sent',
    'delivered': 'Delivered',
    'read': 'Read',
    'failed': 'Failed',
    'unknown': 'Result unknown',
    'skipped': 'Skipped',
  };
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'WhatsApp reminder delivery',
              style: TextStyle(
                fontFamily: 'CormorantGaramond',
                fontSize: 28,
                color: academyEmerald,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh delivery status',
            onPressed: () =>
                setState(() => data = widget.fetch('/admin/reminders')),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      const SizedBox(height: 18),
      FutureBuilder<dynamic>(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Text('Could not load delivery status. ${snapshot.error}');
          }
          final result = snapshot.data as Map;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 0,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result['configured'] == true
                            ? 'WhatsApp reminders configured'
                            : 'WhatsApp reminders are not configured',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Reminder window: ${result['minutes']} minutes before class.',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Only opted-in numbers receive reminders. The academy computer must remain running.',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        result['receipts_configured'] == true
                            ? 'Signed delivery receipts configured. Confirm the webhook subscription in WhatsApp Manager.'
                            : 'Delivery receipts are not configured. Accepted does not mean delivered.',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Latest 100 reminders',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if ((result['deliveries'] as List).isEmpty)
                const Text(
                  'No reminders queued yet. Add opt-in phone numbers and wait until a class enters the reminder window.',
                ),
              for (final row in result['deliveries'])
                Card(
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['class_title'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text('${row['recipient']} · ${row['phone']}'),
                        const SizedBox(height: 6),
                        Text(
                          labels[row['state']] ?? row['state'] as String,
                          style: TextStyle(
                            color: ['failed', 'unknown'].contains(row['state'])
                                ? Colors.redAccent
                                : academyEmerald,
                          ),
                        ),
                        if ((row['error_code'] as String).isNotEmpty)
                          Text(
                            'Status code: ${row['error_code']}',
                            style: const TextStyle(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}
