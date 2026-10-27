import 'package:flutter/material.dart';
import 'academy_design.dart';

const supervisionNotice =
    'Academy administrators can review teacher–student and teacher–parent conversations for academy supervision.';

class ConversationReview extends StatefulWidget {
  final Future<dynamic> Function(String) fetch;
  const ConversationReview({super.key, required this.fetch});
  @override
  State<ConversationReview> createState() => _ConversationReviewState();
}

class _ConversationReviewState extends State<ConversationReview> {
  List<dynamic> pairs = [], messages = [];
  Map? selected;
  bool loading = true, moreThreads = true, older = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    loadPairs();
  }

  Future<void> loadPairs({bool append = false}) async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final list =
          await widget.fetch(
                '/admin/conversations?offset=${append ? pairs.length : 0}',
              )
              as List;
      if (mounted) {
        setState(() {
          pairs = append ? [...pairs, ...list] : list;
          moreThreads = list.length == 100;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> open(Map pair, {bool previous = false}) async {
    setState(() {
      loading = true;
      error = '';
      selected = pair;
      if (!previous) messages = [];
    });
    try {
      final suffix = previous && messages.isNotEmpty
          ? '?before_id=${messages.first['id']}'
          : '';
      final list =
          await widget.fetch(
                '/admin/conversations/${pair['first']['id']}/${pair['second']['id']}$suffix',
              )
              as List;
      if (mounted) {
        setState(() {
          messages = previous ? [...list, ...messages] : list;
          older = list.length == 100;
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
        'Conversation review',
        style: TextStyle(
          fontFamily: 'CormorantGaramond',
          fontSize: 30,
          color: academyEmerald,
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Read-only academy supervision. Opening a conversation is recorded in the audit log.',
        style: TextStyle(fontSize: 12),
      ),
      const SizedBox(height: 20),
      if (loading) const LinearProgressIndicator(),
      if (error.isNotEmpty)
        Text(error, style: const TextStyle(color: Colors.red)),
      if (selected == null) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: loading ? null : () => loadPairs(),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh conversations'),
          ),
        ),
        if (!loading && pairs.isEmpty)
          const Text('No teacher–student or teacher–parent conversations yet.'),
        for (final pair in pairs)
          Card(
            elevation: 0,
            color: Colors.white,
            child: ListTile(
              leading: const Icon(Icons.forum_outlined, color: academyEmerald),
              title: Text(
                '${pair['first']['name']} ↔ ${pair['second']['name']}',
              ),
              subtitle: Text(
                '${pair['first']['role']} / ${pair['second']['role']} · ${pair['count']} messages',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: loading ? null : () => open(pair),
            ),
          ),
        if (moreThreads && !loading)
          TextButton(
            onPressed: () => loadPairs(append: true),
            child: const Text('Load more conversations'),
          ),
      ] else ...[
        TextButton.icon(
          onPressed: loading ? null : () => setState(() => selected = null),
          icon: const Icon(Icons.arrow_back),
          label: const Text('All conversations'),
        ),
        Text(
          '${selected!['first']['name']} ↔ ${selected!['second']['name']}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (older)
          TextButton(
            onPressed: loading ? null : () => open(selected!, previous: true),
            child: const Text('Load earlier messages'),
          ),
        const SizedBox(height: 14),
        for (final m in messages)
          Card(
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m['sender_id'] == selected!['first']['id']
                        ? selected!['first']['name'] as String
                        : selected!['second']['name'] as String,
                    style: const TextStyle(
                      fontSize: 11,
                      color: academyEmerald,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(m['text'] as String),
                  const SizedBox(height: 8),
                  Text(
                    '${m['created_at']} UTC',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
      ],
    ],
  );
}
