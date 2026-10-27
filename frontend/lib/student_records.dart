import 'package:flutter/material.dart';
import 'academy_design.dart';

class StudentRecords extends StatefulWidget {
  final List<dynamic> students;
  final int? initialStudentId;
  final Future<dynamic> Function(String) fetch;
  const StudentRecords({
    super.key,
    required this.students,
    required this.fetch,
    this.initialStudentId,
  });
  @override
  State<StudentRecords> createState() => _StudentRecordsState();
}

class _StudentRecordsState extends State<StudentRecords> {
  int? selected;
  late Future<dynamic> record;
  @override
  void initState() {
    super.initState();
    if (widget.students.isNotEmpty) {
      choose(
        widget.students.any((s) => s['id'] == widget.initialStudentId)
            ? widget.initialStudentId!
            : widget.students.first['id'] as int,
      );
    }
  }

  void choose(int id) {
    selected = id;
    record = widget.fetch('/students/$id/summary');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.students.isEmpty) {
      return const Text(
        'No student records are linked to this account. Ask the administrator to link the family and teacher.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Student record & summary',
          style: TextStyle(
            fontFamily: 'CormorantGaramond',
            fontSize: 30,
            color: academyEmerald,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Attendance, lessons, homework, and Quran progress for this learner.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<int>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Student / child'),
          items: widget.students
              .map(
                (s) => DropdownMenuItem<int>(
                  value: s['id'] as int,
                  child: Text(s['name'] as String),
                ),
              )
              .toList(),
          onChanged: (id) {
            if (id != null) setState(() => choose(id));
          },
        ),
        const SizedBox(height: 20),
        FutureBuilder<dynamic>(
          future: record,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Column(
                children: [
                  Text('Could not load the student record. ${snapshot.error}'),
                  TextButton(
                    onPressed: () => setState(() => choose(selected!)),
                    child: const Text('Retry'),
                  ),
                ],
              );
            }
            final data = snapshot.data as Map;
            final stats = data['attendance'] as Map;
            final work = data['homework'] as Map;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _recordCard(
                  Column(
                    children: [
                      AcademyAvatar(
                        name: data['student']['name'] as String,
                        radius: 32,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        data['student']['name'] as String,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(data['student']['level'] as String? ?? 'Student'),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final item in [
                      ('Present', stats['present']),
                      ('Absent', stats['absent']),
                      ('Not recorded', stats['unrecorded']),
                      (
                        'Attendance',
                        stats['rate'] == null ? '—' : '${stats['rate']}%',
                      ),
                    ])
                      SizedBox(
                        width: 130,
                        child: _recordCard(
                          Column(
                            children: [
                              Text(
                                '${item.$2}',
                                style: const TextStyle(
                                  fontSize: 23,
                                  color: academyEmerald,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                item.$1,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const Text(
                  'Attendance rate uses marked, completed lessons only. Unrecorded lessons are not counted as absences.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF77867D)),
                ),
                const SizedBox(height: 20),
                _recordCard(AttendanceChart(months: data['months'] as List)),
                Text(
                  'Reporting timezone: ${data['timezone']}',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 20),
                _recordCard(
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.assignment_outlined,
                      color: academyEmerald,
                    ),
                    title: Text(
                      'Homework: ${work['completed']} of ${work['total']} completed',
                    ),
                    subtitle: Text(
                      '${data['resources']} assigned learning resources',
                    ),
                  ),
                ),
                const Text(
                  'Quran progress',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if ((data['progress'] as List).isEmpty)
                  const Text('No progress recorded yet.'),
                for (final p in data['progress'])
                  _recordCard(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${p['surah']} · ${p['percent']}%'),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: (p['percent'] as num) / 100,
                        ),
                        const SizedBox(height: 10),
                        Text(p['notes'] as String),
                      ],
                    ),
                  ),
                const SizedBox(height: 15),
                const Text(
                  'Lesson history & upcoming classes',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if ((data['lessons'] as List).isEmpty)
                  const Text('No lessons recorded yet.'),
                for (final c in data['lessons'])
                  _recordCard(
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(c['title'] as String),
                      subtitle: Text(_lessonDate(c['starts_at'] as String)),
                      trailing: Text(
                        c['status'] == 'unrecorded'
                            ? 'Not recorded'
                            : c['status'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          color: c['status'] == 'absent'
                              ? Colors.redAccent
                              : academyEmerald,
                        ),
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
}

String _lessonDate(String value) {
  final date = DateTime.parse(
    value.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(value)
        ? value
        : '${value}Z',
  ).toLocal();
  return '${date.day}/${date.month}/${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

Widget _recordCard(Widget child) => Container(
  margin: const EdgeInsets.only(bottom: 14),
  padding: const EdgeInsets.all(18),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0xFFE6EBE2)),
  ),
  child: child,
);

class AttendanceChart extends StatelessWidget {
  final List<dynamic> months;
  const AttendanceChart({super.key, required this.months});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Attendance by month',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          for (final item in [
            ('Present', academyEmerald),
            ('Absent', Colors.redAccent),
            ('Not recorded', academyGold),
          ])
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 9, color: item.$2),
                const SizedBox(width: 5),
                Text(item.$1, style: const TextStyle(fontSize: 10)),
              ],
            ),
        ],
      ),
      const SizedBox(height: 16),
      if (months.isEmpty) const Text('No completed lessons to chart yet.'),
      for (final month in months)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Semantics(
            label:
                '${month['month']}: ${month['present']} present, ${month['absent']} absent, ${month['unrecorded']} not recorded',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${month['month']} · ${month['present']}/${month['total']} present',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 20,
                    child: Row(
                      children: [
                        for (final item in [
                          ('present', academyEmerald),
                          ('absent', Colors.redAccent),
                          ('unrecorded', academyGold),
                        ])
                          if ((month[item.$1] as num) > 0)
                            Expanded(
                              flex: (month[item.$1] as num).toInt(),
                              child: ColoredBox(
                                color: item.$2,
                                child: const SizedBox.expand(),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
