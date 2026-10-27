import 'conversation_review.dart';
import 'package:flutter/material.dart';
import 'message_events.dart';

/// Private academy conversations remain available while the call stays open.
class ClassChat extends StatefulWidget {
  final String baseUrl, token;
  final Future<dynamic> Function(String) fetch;
  final Future<void> Function(int, String) send;
  const ClassChat({
    super.key,
    required this.baseUrl,
    required this.token,
    required this.fetch,
    required this.send,
  });
  @override
  State<ClassChat> createState() => _ClassChatState();
}

class _ClassChatState extends State<ClassChat> {
  final composer = TextEditingController();
  List<dynamic> contacts = [], messages = [];
  int? contact;
  int revision = 0;
  bool sending = false, connected = false;
  String error = '';
  MessageEvents? events;
  @override
  void initState() {
    super.initState();
    loadContacts();
    events = MessageEvents(
      baseUrl: widget.baseUrl,
      token: widget.token,
      onChanged: refresh,
      onExpired: () {
        if (mounted) {
          setState(
            () => error =
                'Session expired. Leave the classroom and sign in again.',
          );
        }
      },
      onConnected: (v) {
        if (mounted) setState(() => connected = v);
      },
    )..connect();
  }

  Future<void> loadContacts() async {
    try {
      final data = await widget.fetch('/contacts') as List;
      if (!mounted) return;
      setState(() {
        contacts = data;
        contact = data.isEmpty ? null : data.first['id'] as int;
      });
      await refresh();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> refresh() async {
    final id = contact, request = ++revision;
    if (id == null) return;
    try {
      final data = await widget.fetch('/messages/$id') as List;
      if (mounted && request == revision && id == contact) {
        setState(() {
          messages = data;
          error = '';
        });
      }
    } catch (e) {
      if (mounted && request == revision) setState(() => error = e.toString());
    }
  }

  Future<void> send() async {
    if (sending || contact == null || composer.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      await widget.send(contact!, composer.text.trim());
      composer.clear();
      await refresh();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    events?.close();
    composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        18,
        18,
        18 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(supervisionNotice, style: TextStyle(fontSize: 10)),
          ),
          const Text(
            'Private chat',
            style: TextStyle(
              fontFamily: 'CormorantGaramond',
              fontSize: 28,
              color: Color(0xFF145B45),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            connected
                ? 'Live · Your call continues while you chat'
                : 'Connecting live updates…',
            style: const TextStyle(fontSize: 11, color: Color(0xFF77867D)),
          ),
          const SizedBox(height: 18),
          if (contacts.isNotEmpty)
            DropdownButtonFormField<int>(
              initialValue: contact,
              isExpanded: true,
              items: contacts
                  .map(
                    (c) => DropdownMenuItem(
                      value: c['id'] as int,
                      child: Text(
                        c['name'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                setState(() => contact = v);
                refresh();
              },
              decoration: const InputDecoration(labelText: 'Academy contact'),
            ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                error,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          Expanded(
            child: contacts.isEmpty
                ? const Center(child: Text('No authorized contacts yet.'))
                : ListView(
                    children: [
                      for (final m in messages)
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF1E9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            m['text'] as String,
                            style: const TextStyle(height: 1.7),
                          ),
                        ),
                    ],
                  ),
          ),
          TextField(
            controller: composer,
            maxLength: 2000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Your message'),
          ),
          FilledButton.icon(
            onPressed: sending || contact == null ? null : send,
            icon: const Icon(Icons.send_outlined, size: 17),
            label: Text(sending ? 'Sending…' : 'Send message'),
          ),
        ],
      ),
    ),
  );
}
