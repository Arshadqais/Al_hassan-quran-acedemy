import 'package:flutter/material.dart';
import 'academy_design.dart';

class RecurringSchedules extends StatefulWidget {
  final Future<dynamic> Function(String) fetch;
  final Future<void> Function(String, Map<String, dynamic>) save;
  final List<dynamic> students, teachers;
  final bool editor;
  const RecurringSchedules({
    super.key,
    required this.fetch,
    required this.save,
    required this.students,
    required this.teachers,
    required this.editor,
  });
  @override
  State<RecurringSchedules> createState() => _RecurringSchedulesState();
}

class _RecurringSchedulesState extends State<RecurringSchedules> {
  late Future<dynamic> records;
  bool busy = false;
  String error = '';
  static const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    records = widget.fetch('/schedules');
  }

  Future<void> change(String path, Map<String, dynamic> body) async {
    setState(() => busy = true);
    try {
      await widget.save(path, body);
      if (mounted) {
        setState(() {
          error = '';
          reload();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Weekly class schedules',
        style: TextStyle(
          fontFamily: 'CormorantGaramond',
          fontSize: 30,
          color: academyEmerald,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Set weekdays and time once. Upcoming lessons are generated automatically, 45 days ahead, whenever Classes is opened.',
        style: TextStyle(fontSize: 12, height: 1.7),
      ),
      const SizedBox(height: 20),
      if (widget.editor)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    if (widget.students.isEmpty || widget.teachers.isEmpty) {
                      setState(
                        () => error =
                            'Create and link a teacher and student first.',
                      );
                      return;
                    }
                    final data = await showDialog<Map<String, dynamic>>(
                      context: context,
                      builder: (_) => _RecurringDialog(
                        students: widget.students,
                        teachers: widget.teachers,
                      ),
                    );
                    if (data != null && mounted) {
                      await change('/schedules', data);
                    }
                  },
            icon: const Icon(Icons.repeat),
            label: const Text('Set weekly schedule'),
          ),
        ),
      if (error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(error, style: const TextStyle(color: Colors.red)),
        ),
      const SizedBox(height: 16),
      FutureBuilder<dynamic>(
        future: records,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Column(
              children: [
                Text('Could not load schedules. ${snapshot.error}'),
                TextButton(
                  onPressed: () => setState(reload),
                  child: const Text('Retry'),
                ),
              ],
            );
          }
          final list = snapshot.data as List;
          if (list.isEmpty) {
            return const Text(
              'No weekly schedules yet. One-off classes remain available in Classes.',
            );
          }
          return Column(
            children: [
              for (final r in list)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        r['title'] as String,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${r['teacher']} · ${r['duration']} min · ${r['category']}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(r['weekdays'] as List).map((d) => days[d as int]).join(' · ')} at ${r['local_time']}',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Timezone: ${r['timezone']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'From ${r['start_date']}${r['end_date'] == null ? ' · No end date' : ' to ${r['end_date']}'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        r['active'] == true ? 'Active' : 'Stopped',
                        style: TextStyle(
                          color: r['active'] == true
                              ? academyEmerald
                              : Colors.grey,
                        ),
                      ),
                      if (widget.editor && r['active'] == true)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: busy
                                ? null
                                : () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text(
                                          'Stop this schedule?',
                                        ),
                                        content: const Text(
                                          'Future lessons will be cancelled. Past lessons, attendance, and records are preserved.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, false),
                                            child: const Text('Keep schedule'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            child: const Text('Stop schedule'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true && mounted) {
                                      await change(
                                        '/schedules/${r['id']}/stop',
                                        {},
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: const Text('Stop future lessons'),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _RecurringDialog extends StatefulWidget {
  final List<dynamic> students, teachers;
  const _RecurringDialog({required this.students, required this.teachers});
  @override
  State<_RecurringDialog> createState() => _RecurringDialogState();
}

class _RecurringDialogState extends State<_RecurringDialog> {
  final form = GlobalKey<FormState>();
  String title = '',
      zone = 'Asia/Karachi',
      duration = '30',
      category = 'Individual';
  int? teacher;
  final students = <int>{}, weekdays = <int>{0, 1, 2, 3, 4};
  DateTime start = DateUtils.dateOnly(DateTime.now());
  DateTime? end;
  TimeOfDay time = const TimeOfDay(hour: 9, minute: 0);
  String error = '';
  String date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Set weekly schedule'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'Class title'),
                maxLength: 100,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a title' : null,
                onSaved: (v) => title = v!.trim(),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Teacher'),
                items: widget.teachers
                    .map(
                      (t) => DropdownMenuItem<int>(
                        value: t['id'] as int,
                        child: Text(t['name'] as String),
                      ),
                    )
                    .toList(),
                validator: (v) => v == null ? 'Select a teacher' : null,
                onChanged: (v) => teacher = v,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Class type'),
                items: ['Individual', 'Group']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => category = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: duration,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duration (10–180 minutes)',
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return n == null || n < 10 || n > 180
                      ? 'Enter 10–180 minutes'
                      : null;
                },
                onSaved: (v) => duration = v!,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: zone,
                decoration: const InputDecoration(
                  labelText: 'IANA timezone',
                  helperText:
                      'For example Asia/Karachi, Europe/London, America/New_York',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a timezone' : null,
                onSaved: (v) => zone = v!.trim(),
              ),
              const SizedBox(height: 18),
              const Text('Repeat on'),
              Wrap(
                spacing: 6,
                children: [
                  for (var i = 0; i < 7; i++)
                    FilterChip(
                      label: Text(_RecurringSchedulesState.days[i]),
                      selected: weekdays.contains(i),
                      onSelected: (on) => setState(() {
                        if (on) {
                          weekdays.add(i);
                        } else {
                          weekdays.remove(i);
                        }
                      }),
                    ),
                ],
              ),
              OutlinedButton(
                onPressed: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: time,
                  );
                  if (t != null && mounted) setState(() => time = t);
                },
                child: Text('Time: ${time.format(context)}'),
              ),
              OutlinedButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: start,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null && mounted) setState(() => start = d);
                },
                child: Text('Start: ${date(start)}'),
              ),
              OutlinedButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: end ?? start,
                    firstDate: start,
                    lastDate: start.add(const Duration(days: 3650)),
                  );
                  if (d != null && mounted) setState(() => end = d);
                },
                child: Text(
                  end == null ? 'No end date (optional)' : 'End: ${date(end!)}',
                ),
              ),
              if (end != null)
                TextButton(
                  onPressed: () => setState(() => end = null),
                  child: const Text('Remove end date'),
                ),
              const SizedBox(height: 12),
              const Text('Students linked to this teacher'),
              for (final s in widget.students)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s['name'] as String),
                  value: students.contains(s['id']),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      students.add(s['id'] as int);
                    } else {
                      students.remove(s['id']);
                    }
                  }),
                ),
              if (error.isNotEmpty)
                Text(error, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          form.currentState!.save();
          if (weekdays.isEmpty ||
              students.isEmpty ||
              (category == 'Individual' && students.length != 1) ||
              (end != null && end!.isBefore(start))) {
            setState(
              () => error =
                  'Select weekdays and students; individual classes need one learner. End date must follow start.',
            );
            return;
          }
          Navigator.pop(context, {
            'title': title,
            'teacher_id': teacher,
            'student_ids': students.toList(),
            'start_date': date(start),
            'end_date': end == null ? null : date(end!),
            'local_time':
                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
            'timezone': zone,
            'weekdays': weekdays.toList()..sort(),
            'duration': int.parse(duration),
            'category': category,
          });
        },
        child: const Text('Save repeating schedule'),
      ),
    ],
  );
}
