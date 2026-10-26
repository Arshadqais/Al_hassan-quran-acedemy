import 'classroom.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _green = Color(0xFF145B45);
const _cream = Color(0xFFF8F7F2);
const _muted = Color(0xFF77867D);
const academyApiBaseUrl = String.fromEnvironment('API_BASE_URL');

class AcademyApi {
  final String baseUrl;
  final http.Client client;
  String? token;
  AcademyApi(this.baseUrl, {http.Client? client})
    : client = client ?? http.Client();
  bool get configured {
    final uri = Uri.tryParse(baseUrl);
    return uri != null &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        (uri.scheme == 'https' ||
            (kDebugMode &&
                uri.scheme == 'http' &&
                ['127.0.0.1', 'localhost'].contains(uri.host)));
  }

  Future<dynamic> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (!configured) {
      throw const ApiFailure('The academy server is not configured.');
    }
    final request = http.Request(
      method,
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api$path'),
    );
    request.headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 20)),
    );
    dynamic data;
    try {
      data = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      throw const ApiFailure('The server returned an invalid response.');
    }
    if (response.statusCode == 401 && token != null) {
      token = null;
      throw const ApiFailure('Your session has expired. Please sign in again.');
    }
    if (response.statusCode >= 400) {
      throw ApiFailure(
        data is Map && data['detail'] is String
            ? data['detail'] as String
            : 'Please check your entries and try again.',
      );
    }
    return data;
  }

  void close() {
    token = null;
    client.close();
  }
}

class ApiFailure implements Exception {
  final String message;
  const ApiFailure(this.message);
  @override
  String toString() => message;
}

class LivePortal extends StatefulWidget {
  final AcademyApi? api;
  const LivePortal({super.key, this.api});
  @override
  State<LivePortal> createState() => _LivePortalState();
}

class _LivePortalState extends State<LivePortal> {
  late final api = widget.api ?? AcademyApi(academyApiBaseUrl);
  Map<String, dynamic>? user;
  List<dynamic> users = [],
      classes = [],
      attendance = [],
      homework = [],
      resources = [],
      contacts = [],
      progress = [],
      messages = [];
  Map<String, dynamic> report = {};
  int? studentId, contactId;
  String page = 'Overview', email = '', password = '', error = '';
  bool busy = false, obscure = true;
  final loginForm = GlobalKey<FormState>();
  final compose = TextEditingController();
  String get role => user?['role'] as String? ?? '';
  bool get editor => ['admin', 'teacher'].contains(role);
  List<dynamic> get students =>
      users.where((u) => u['role'] == 'student').toList();
  List<dynamic> get teachers =>
      users.where((u) => u['role'] == 'teacher').toList();
  List<String> get pages => [
    'Overview',
    if (role == 'admin') ...['People', 'Assignments'],
    'Classes',
    'Progress',
    'Attendance',
    'Resources',
    'Homework',
    'Messages',
    if (role == 'parent') 'Feedback',
    if (role == 'admin') 'Reports',
    'Account',
  ];
  @override
  void dispose() {
    api.close();
    compose.dispose();
    super.dispose();
  }

  void notify(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> execute(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is ApiFailure
              ? e.message
              : 'Could not reach the academy server. Check your connection and try again.';
          if (api.token == null) user = null;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> login() async {
    if (!api.configured || !loginForm.currentState!.validate()) return;
    await execute(() async {
      final data = await api.call(
        '/auth/login',
        method: 'POST',
        body: {'email': email.trim(), 'password': password},
      );
      api.token = data['token'] as String;
      password = '';
      user = Map<String, dynamic>.from(data['user'] as Map);
      await refresh();
    });
  }

  Future<void> refresh() async {
    final results = await Future.wait([
      api.call('/users'),
      api.call('/classes'),
      api.call('/attendance'),
      api.call('/homework'),
      api.call('/resources'),
      api.call('/contacts'),
    ]);
    users = results[0] as List;
    classes = results[1] as List;
    attendance = results[2] as List;
    homework = results[3] as List;
    resources = results[4] as List;
    contacts = results[5] as List;
    if (!students.any((s) => s['id'] == studentId)) {
      studentId = students.isEmpty ? null : students.first['id'] as int;
    }
    if (!contacts.any((c) => c['id'] == contactId)) {
      contactId = contacts.isEmpty ? null : contacts.first['id'] as int;
    }
    progress = studentId == null
        ? []
        : await api.call('/students/$studentId/progress') as List;
    messages = contactId == null
        ? []
        : await api.call('/messages/$contactId') as List;
    if (role == 'admin') {
      report = Map<String, dynamic>.from(
        await api.call('/admin/reports') as Map,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> save(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
  }) => execute(() async {
    await api.call(path, method: method, body: body);
    await refresh();
    notify('Saved to the academy server.');
  });
  String person(dynamic id) =>
      users
          .where((u) => u['id'] == id)
          .map((u) => u['name'] as String)
          .firstOrNull ??
      contacts
          .where((u) => u['id'] == id)
          .map((u) => u['name'] as String)
          .firstOrNull ??
      'Academy member';
  String className(dynamic id) =>
      classes
          .where((c) => c['id'] == id)
          .map((c) => c['title'] as String)
          .firstOrNull ??
      'Class';
  Widget box(Widget child) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xFFE4EADF)),
    ),
    child: Padding(padding: const EdgeInsets.all(22), child: child),
  );
  Widget heading(String title, String description) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'CormorantGaramond',
            fontSize: 30,
            color: _green,
          ),
        ),
        const SizedBox(height: 8),
        Text(description, style: const TextStyle(color: _muted, fontSize: 12)),
      ],
    ),
  );
  Widget blank(String text) => box(
    Padding(
      padding: const EdgeInsets.all(14),
      child: Text(text, style: const TextStyle(color: _muted)),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (user == null) return loginPage();
    final wide = MediaQuery.sizeOf(context).width > 900;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Al Hassan · Academy portal',
          style: TextStyle(fontFamily: 'CormorantGaramond', fontSize: 20),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh academy records',
            onPressed: busy ? null : () => execute(refresh),
            icon: const Icon(Icons.refresh),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => execute(() async {
                    await api.call('/auth/logout', method: 'POST');
                    api.token = null;
                    user = null;
                    users = [];
                    messages = [];
                    password = '';
                  }),
            child: const Text('Sign out'),
          ),
        ],
      ),
      drawer: wide ? null : Drawer(child: navigation()),
      body: Row(
        children: [
          if (wide) SizedBox(width: 210, child: navigation()),
          Expanded(
            child: Column(
              children: [
                if (busy) const LinearProgressIndicator(),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      error,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(wide ? 30 : 16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${user!['name']} · ${role.toUpperCase()} · Connected to academy server',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 24),
                            content(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget navigation() => Material(
    color: Colors.white,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Icon(Icons.mosque_outlined, color: _green, size: 36),
        ),
        Expanded(
          child: ListView(
            children: pages
                .map(
                  (p) => ListTile(
                    selected: page == p,
                    selectedColor: _green,
                    selectedTileColor: const Color(0xFFEAF1E9),
                    title: Text(p, style: const TextStyle(fontSize: 13)),
                    onTap: () {
                      setState(() => page = p);
                      if (MediaQuery.sizeOf(context).width <= 900) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                )
                .toList(),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'LIVE PORTAL\nRecords are stored on your academy server.',
            style: TextStyle(color: _muted, fontSize: 10, height: 1.8),
          ),
        ),
      ],
    ),
  );
  Widget loginPage() => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Al Hassan Online Quran Academy',
        style: TextStyle(fontSize: 17, fontFamily: 'CormorantGaramond'),
      ),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 430,
          child: box(
            Form(
              key: loginForm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.mosque_outlined, color: _green, size: 55),
                  const SizedBox(height: 24),
                  const Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'CormorantGaramond',
                      fontSize: 32,
                      color: _green,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sign in to your academy account',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 28),
                  if (!api.configured) ...[
                    const Text(
                      'The live academy server has not been connected yet. You can explore the interactive demo from the home page. Real accounts will be available when the academy administrator connects the backend.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.8,
                        color: _muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to explore demo'),
                    ),
                  ] else ...[
                    TextFormField(
                      key: const ValueKey('login-email'),
                      onChanged: (v) => email = v,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      validator: (v) => v == null || !v.contains('@')
                          ? 'Enter your email address.'
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('login-password'),
                      onChanged: (v) => password = v,
                      obscureText: obscure,
                      autofillHints: const [AutofillHints.password],
                      validator: (v) => v == null || v.isEmpty
                          ? 'Enter your password.'
                          : null,
                      onFieldSubmitted: (_) => busy ? null : login(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: 'Toggle password visibility',
                          onPressed: () => setState(() => obscure = !obscure),
                          icon: Icon(
                            obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          error,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    FilledButton(
                      onPressed: busy ? null : login,
                      child: Text(busy ? 'Signing in…' : 'Sign in'),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Accounts are issued by the academy administrator. For access or password help, contact your academy.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _muted,
                        fontSize: 11,
                        height: 1.8,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Widget studentPicker() => students.isEmpty
      ? blank('No students are linked to this account yet.')
      : Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: DropdownButtonFormField<int>(
            initialValue: studentId,
            items: students
                .map(
                  (s) => DropdownMenuItem(
                    value: s['id'] as int,
                    child: Text(s['name'] as String),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (v) => execute(() async {
                    studentId = v;
                    progress = await api.call('/students/$v/progress') as List;
                  }),
            decoration: InputDecoration(
              labelText: role == 'parent' ? 'My child' : 'Student',
            ),
          ),
        );
  Widget content() => switch (page) {
    'People' => peoplePage(),
    'Assignments' => assignmentPage(),
    'Classes' => classPage(),
    'Progress' => progressPage(),
    'Attendance' => attendancePage(),
    'Resources' => resourcePage(),
    'Homework' => homeworkPage(),
    'Messages' => messagePage(),
    'Feedback' => feedbackPage(),
    'Reports' => reportPage(),
    'Account' => accountPage(),
    _ => overview(),
  };
  Widget overview() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Assalamu Alaikum, ${user!['name']}',
        'Welcome to your academy. Your records are private to your account.',
      ),
      Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _green,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              color: Color(0xFFEAD8AC),
              size: 40,
            ),
            SizedBox(height: 18),
            Text(
              'Every ayah is a step closer.',
              style: TextStyle(
                fontFamily: 'CormorantGaramond',
                fontSize: 30,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Learn. Practice. Grow.',
              style: TextStyle(color: Color(0xFFCADCCD), letterSpacing: 2),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          stat('Classes', '${classes.length}'),
          stat(
            role == 'parent' ? 'My children' : 'Students',
            '${students.length}',
          ),
          stat(
            'Homework',
            '${homework.where((h) => h['completed'] == false).length} pending',
          ),
        ],
      ),
      const SizedBox(height: 20),
      heading(
        'Your next classes',
        'Times are shown in your device’s timezone.',
      ),
      if (classes.isEmpty)
        blank(
          'No classes scheduled yet. Your teacher or administrator can add your next lesson.',
        ),
      ...classes.take(3).map(classCard),
    ],
  );
  Widget stat(String label, String value) => SizedBox(
    width: 210,
    child: box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              color: _green,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: _muted)),
        ],
      ),
    ),
  );
  Widget peoplePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Academy people',
        'Create accounts and link families with their teachers.',
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: busy ? null : addAccount,
          icon: const Icon(Icons.add),
          label: const Text('Create account'),
        ),
      ),
      const SizedBox(height: 20),
      ...users.map(
        (u) => box(
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: _cream,
              child: Text(
                (u['name'] as String)[0],
                style: const TextStyle(color: _green),
              ),
            ),
            title: Text(u['name'] as String),
            subtitle: Text('${u['role']} · ${u['email']}'),
          ),
        ),
      ),
    ],
  );
  Future<Map<String, String>?> formDialog(
    String title,
    List<(String, String, bool)> fields, {
    List<String>? options,
    String? optionLabel,
  }) async {
    final values = {for (final f in fields) f.$1: f.$2};
    String option = options?.firstOrNull ?? '';
    final form = GlobalKey<FormState>();
    return showDialog<Map<String, String>>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final field in fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextFormField(
                        initialValue: field.$2,
                        obscureText: field.$3,
                        maxLength: field.$3
                            ? 128
                            : field.$1 == 'Content'
                            ? 20000
                            : field.$1 == 'Message'
                            ? 1500
                            : 160,
                        minLines: field.$1 == 'Content' ? 4 : 1,
                        maxLines: field.$1 == 'Content' ? 8 : 1,
                        onChanged: (v) => values[field.$1] = v,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Required'
                            : field.$3 && v.length < 12
                            ? 'Use at least 12 characters.'
                            : null,
                        decoration: InputDecoration(labelText: field.$1),
                      ),
                    ),
                  if (options != null)
                    DropdownButtonFormField<String>(
                      initialValue: option,
                      items: options
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      onChanged: (v) => option = v!,
                      decoration: InputDecoration(
                        labelText: optionLabel ?? 'Role',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(c, {...values, 'option': option});
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> addAccount() async {
    final data = await formDialog(
      'Create academy account',
      [
        ('Name', '', false),
        ('Email', '', false),
        ('Initial password', '', true),
        ('Level / specialty', 'Level 1', false),
      ],
      options: ['student', 'teacher', 'parent', 'admin'],
    );
    if (data != null && mounted) {
      await save('/users', {
        'name': data['Name'],
        'email': data['Email'],
        'password': data['Initial password'],
        'role': data['option'],
        'level': data['Level / specialty'],
      });
    }
  }

  Widget assignmentPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Link your academy',
        'Assign teachers and parents to students. This controls record access.',
      ),
      if (students.isEmpty ||
          !users.any((u) => ['teacher', 'parent'].contains(u['role'])))
        blank('Create a student and a teacher or parent first.')
      else
        box(
          _AssignmentForm(
            users: users,
            onSave: (adult, student) => save('/assignments', {
              'adult_id': adult,
              'student_id': student,
            }),
          ),
        ),
    ],
  );
  Widget classPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading('My classes', 'Your schedule, in your device’s local time.'),
      if (editor)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy ? null : scheduleClass,
            icon: const Icon(Icons.add),
            label: const Text('Schedule class'),
          ),
        ),
      const SizedBox(height: 20),
      if (classes.isEmpty) blank('No classes have been scheduled.'),
      ...classes.map(classCard),
    ],
  );
  Widget classCard(dynamic c) {
    final date = DateTime.parse('${c['starts_at']}Z').toLocal();
    return box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c['title'] as String,
            style: const TextStyle(
              fontFamily: 'CormorantGaramond',
              fontSize: 22,
              color: _green,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${c['teacher']} · ${c['category']} · ${c['duration']} min',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            '${date.day}/${date.month}/${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (role != 'parent')
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => execute(() async {
                      final data = await api.call(
                        '/classes/${c['id']}/room-token',
                        method: 'POST',
                      );
                      if (!mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Classroom(
                            url: data['url'] as String,
                            token: data['token'] as String,
                            title: c['title'] as String,
                            canShareScreen: editor,
                          ),
                        ),
                      );
                    }),
              icon: const Icon(Icons.videocam_outlined, size: 18),
              label: const Text('Join private classroom'),
            ),
        ],
      ),
    );
  }

  Future<void> scheduleClass() async {
    if (students.isEmpty || (role == 'admin' && teachers.isEmpty)) {
      notify('Create and assign a teacher and student first.');
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => _ScheduleDialog(
        students: students,
        teachers: role == 'teacher' ? [user!] : teachers,
      ),
    );
    if (result != null && mounted) await save('/classes', result);
  }

  Widget progressPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading('Quran progress', 'Teacher-recorded learning milestones.'),
      studentPicker(),
      if (editor && studentId != null)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final data = await formDialog('Record Quran progress', [
                      ('Surah', 'Al-Fatiha', false),
                      ('Percent (0–100)', '0', false),
                      ('Notes', 'Practice with your teacher.', false),
                    ]);
                    if (data != null && mounted) {
                      final percent = int.tryParse(data['Percent (0–100)']!);
                      if (percent == null || percent < 0 || percent > 100) {
                        notify('Enter a percentage from 0 to 100.');
                        return;
                      }
                      await save('/students/$studentId/progress', {
                        'surah': data['Surah'],
                        'percent': percent,
                        'notes': data['Notes'],
                      }, method: 'PUT');
                    }
                  },
            child: const Text('Record progress'),
          ),
        ),
      const SizedBox(height: 20),
      if (progress.isEmpty)
        blank('No progress has been recorded for this student.'),
      ...progress.map(
        (p) => box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${p['surah']} · ${p['percent']}%',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: (p['percent'] as num) / 100,
                color: _green,
                backgroundColor: _cream,
              ),
              const SizedBox(height: 12),
              Text(p['notes'] as String, style: const TextStyle(color: _muted)),
            ],
          ),
        ),
      ),
    ],
  );
  Widget attendancePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading('Attendance', 'A record of each lesson attended.'),
      if (editor && classes.isNotEmpty && students.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: busy ? null : markAttendance,
            child: const Text('Record attendance'),
          ),
        ),
      const SizedBox(height: 20),
      if (attendance.isEmpty) blank('No attendance recorded yet.'),
      ...attendance.map(
        (a) => box(
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(className(a['session_id'])),
            subtitle: Text(person(a['student_id'])),
            trailing: Text(
              a['present'] == true ? 'Present' : 'Absent',
              style: TextStyle(
                color: a['present'] == true ? _green : Colors.red,
              ),
            ),
          ),
        ),
      ),
    ],
  );
  Future<void> markAttendance() async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => _AttendanceDialog(classes: classes, students: students),
    );
    if (data != null && mounted) {
      await save('/classes/${data['session']}/attendance', {
        'student_id': data['student'],
        'present': data['present'],
      }, method: 'PUT');
    }
  }

  Widget resourcePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading('Learning resources', 'Study notes assigned by your teacher.'),
      if (editor && students.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final student = await pickStudent();
                    if (student == null) return;
                    final data = await formDialog('Assign a study note', [
                      ('Title', '', false),
                      ('Content', '', false),
                    ]);
                    if (data != null && mounted) {
                      await save('/resources', {
                        'student_id': student,
                        'title': data['Title'],
                        'content': data['Content'],
                      });
                    }
                  },
            child: const Text('Assign study note'),
          ),
        ),
      const SizedBox(height: 20),
      if (resources.isEmpty) blank('No resources assigned yet.'),
      ...resources.map(
        (r) => box(
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined, color: _green),
            title: Text(r['title'] as String),
            subtitle: Text('For ${person(r['student_id'])}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text(r['title'] as String),
                content: SizedBox(
                  width: 550,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      r['content'] as String,
                      style: const TextStyle(height: 1.8),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
  Future<int?> pickStudent() => showDialog<int>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Select a student'),
      children: students
          .map(
            (s) => SimpleDialogOption(
              onPressed: () => Navigator.pop(c, s['id'] as int),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(s['name'] as String),
              ),
            ),
          )
          .toList(),
    ),
  );
  Widget homeworkPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading('Homework', 'Keep learning between your lessons.'),
      if (editor && students.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final student = await pickStudent();
                    if (student == null) return;
                    final data = await formDialog('Assign homework', [
                      ('Title', '', false),
                    ]);
                    if (data != null && mounted) {
                      await save('/homework', {
                        'student_id': student,
                        'title': data['Title'],
                      });
                    }
                  },
            child: const Text('Assign homework'),
          ),
        ),
      const SizedBox(height: 20),
      if (homework.isEmpty) blank('No homework assigned yet.'),
      ...homework.map(
        (h) => box(
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: h['completed'] as bool,
            onChanged: role == 'student' && !busy
                ? (v) => save('/homework/${h['id']}', {
                    'completed': v,
                  }, method: 'PUT')
                : null,
            title: Text(h['title'] as String),
            subtitle: Text(person(h['student_id'])),
          ),
        ),
      ),
    ],
  );
  Widget messagePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Messages',
        'Private conversations with your authorized academy contacts. Refresh to receive new messages.',
      ),
      if (contacts.isEmpty)
        blank(
          'No contacts available. Ask the administrator to link your account.',
        )
      else ...[
        DropdownButtonFormField<int>(
          initialValue: contactId,
          items: contacts
              .map(
                (c) => DropdownMenuItem(
                  value: c['id'] as int,
                  child: Text(c['name'] as String),
                ),
              )
              .toList(),
          onChanged: busy
              ? null
              : (v) => execute(() async {
                  contactId = v;
                  messages = await api.call('/messages/$v') as List;
                }),
          decoration: const InputDecoration(labelText: 'Conversation'),
        ),
        const SizedBox(height: 20),
        box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (messages.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Start a conversation.',
                    style: TextStyle(color: _muted),
                  ),
                ),
              for (final message in messages)
                Align(
                  alignment: message['sender_id'] == user!['id']
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    constraints: const BoxConstraints(maxWidth: 550),
                    decoration: BoxDecoration(
                      color: message['sender_id'] == user!['id']
                          ? const Color(0xFFEAF1E9)
                          : _cream,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      message['text'] as String,
                      style: const TextStyle(height: 1.7),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              TextField(
                controller: compose,
                maxLength: 2000,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Your message'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => execute(() async {
                          if (compose.text.trim().isEmpty) return;
                          await api.call(
                            '/messages',
                            method: 'POST',
                            body: {
                              'recipient_id': contactId,
                              'text': compose.text.trim(),
                            },
                          );
                          compose.clear();
                          await refresh();
                        }),
                  icon: const Icon(Icons.send_outlined, size: 17),
                  label: const Text('Send message'),
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );
  Widget feedbackPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Parent feedback',
        'Share your experience with the academy administrator.',
      ),
      studentPicker(),
      if (studentId != null)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final data = await formDialog('Share feedback', [
                      ('Rating (1–5)', '5', false),
                      ('Message', '', false),
                    ]);
                    if (data != null && mounted) {
                      final rating = int.tryParse(data['Rating (1–5)']!);
                      if (rating == null || rating < 1 || rating > 5) {
                        notify('Enter a rating from 1 to 5.');
                        return;
                      }
                      await save('/feedback', {
                        'student_id': studentId,
                        'rating': rating,
                        'text': data['Message'],
                      });
                    }
                  },
            child: const Text('Write feedback'),
          ),
        ),
    ],
  );
  Widget accountPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading('My account', 'Your academy profile and account security.'),
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user!['name'] as String,
              style: const TextStyle(fontSize: 24, color: _green),
            ),
            const SizedBox(height: 10),
            Text(user!['email'] as String),
            const SizedBox(height: 6),
            Text('Role: $role', style: const TextStyle(color: _muted)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final data = await formDialog('Change your password', [
                        ('Current password', '', true),
                        ('New password', '', true),
                      ]);
                      if (data != null && mounted) {
                        await execute(() async {
                          await api.call(
                            '/auth/password',
                            method: 'POST',
                            body: {
                              'current_password': data['Current password'],
                              'new_password': data['New password'],
                            },
                          );
                          api.token = null;
                          user = null;
                          password = '';
                          notify('Password changed. Please sign in again.');
                        });
                      }
                    },
              child: const Text('Change password'),
            ),
            const SizedBox(height: 14),
            const Text(
              'Changing your password signs out all of your active sessions.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ],
  );
  Widget reportPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Academy reports',
        'Account totals, family feedback, and administrative activity.',
      ),
      Wrap(
        spacing: 14,
        children: [
          stat('Students', '${report['students'] ?? 0}'),
          stat('Teachers', '${report['teachers'] ?? 0}'),
          stat('Classes', '${report['classes'] ?? 0}'),
        ],
      ),
      const SizedBox(height: 20),
      heading('Parent feedback', 'Visible to academy administrators.'),
      for (final f in (report['feedback'] as List? ?? []))
        box(
          Text(
            '${person(f['parent_id'])} · ${f['rating']}/5\n${f['text']}',
            style: const TextStyle(height: 1.8),
          ),
        ),
      const SizedBox(height: 20),
      heading(
        'Audit activity',
        'Sensitive record changes are recorded without message or password contents.',
      ),
      for (final a in (report['audit'] as List? ?? []))
        box(
          Text(
            '${person(a['actor_id'])} · ${a['action']}\n${a['created_at']}',
            style: const TextStyle(fontSize: 12, height: 1.8),
          ),
        ),
    ],
  );
}

class _AssignmentForm extends StatefulWidget {
  final List<dynamic> users;
  final Future<void> Function(int, int) onSave;
  const _AssignmentForm({required this.users, required this.onSave});
  @override
  State<_AssignmentForm> createState() => _AssignmentFormState();
}

class _AssignmentFormState extends State<_AssignmentForm> {
  int? adult, student;
  bool saving = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<int>(
        items: widget.users
            .where((u) => ['teacher', 'parent'].contains(u['role']))
            .map(
              (u) => DropdownMenuItem(
                value: u['id'] as int,
                child: Text('${u['name']} (${u['role']})'),
              ),
            )
            .toList(),
        onChanged: (v) => adult = v,
        decoration: const InputDecoration(labelText: 'Teacher or parent'),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<int>(
        items: widget.users
            .where((u) => u['role'] == 'student')
            .map(
              (u) => DropdownMenuItem(
                value: u['id'] as int,
                child: Text(u['name'] as String),
              ),
            )
            .toList(),
        onChanged: (v) => student = v,
        decoration: const InputDecoration(labelText: 'Student'),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: saving
            ? null
            : () async {
                if (adult == null || student == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Select an adult and a student.'),
                    ),
                  );
                  return;
                }
                setState(() => saving = true);
                await widget.onSave(adult!, student!);
                if (mounted) setState(() => saving = false);
              },
        child: const Text('Link accounts'),
      ),
    ],
  );
}

class _ScheduleDialog extends StatefulWidget {
  final List<dynamic> students, teachers;
  const _ScheduleDialog({required this.students, required this.teachers});
  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  String title = '', duration = '30', category = 'Individual';
  int? teacher;
  final selected = <int>{};
  DateTime? date;
  TimeOfDay time = const TimeOfDay(hour: 9, minute: 0);
  final form = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Schedule a class'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                onChanged: (v) => title = v,
                maxLength: 100,
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Enter a class title.'
                    : null,
                decoration: const InputDecoration(labelText: 'Class title'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                items: widget.teachers
                    .map(
                      (t) => DropdownMenuItem(
                        value: t['id'] as int,
                        child: Text(t['name'] as String),
                      ),
                    )
                    .toList(),
                validator: (v) => v == null ? 'Choose a teacher.' : null,
                onChanged: (v) => teacher = v,
                decoration: const InputDecoration(labelText: 'Teacher'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                items: ['Individual', 'Group']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => category = v!),
                decoration: const InputDecoration(labelText: 'Class type'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: duration,
                onChanged: (v) => duration = v,
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return n == null || n < 10 || n > 180
                      ? 'Use 10–180 minutes.'
                      : null;
                },
                decoration: const InputDecoration(
                  labelText: 'Duration in minutes',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (d != null && mounted) setState(() => date = d);
                },
                child: Text(
                  date == null
                      ? 'Choose date'
                      : '${date!.day}/${date!.month}/${date!.year}',
                ),
              ),
              OutlinedButton(
                onPressed: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: time,
                  );
                  if (t != null && mounted) setState(() => time = t);
                },
                child: Text(time.format(context)),
              ),
              const SizedBox(height: 12),
              const Text(
                'Select students (must be linked to the teacher)',
                style: TextStyle(fontSize: 12),
              ),
              for (final s in widget.students)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s['name'] as String),
                  value: selected.contains(s['id']),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      selected.add(s['id'] as int);
                    } else {
                      selected.remove(s['id']);
                    }
                  }),
                ),
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
          if (date == null ||
              selected.isEmpty ||
              (category == 'Individual' && selected.length != 1)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Choose a date and student(s). Individual classes have one student.',
                ),
              ),
            );
            return;
          }
          Navigator.pop(context, {
            'title': title.trim(),
            'teacher_id': teacher,
            'student_ids': selected.toList(),
            'starts_at': DateTime(
              date!.year,
              date!.month,
              date!.day,
              time.hour,
              time.minute,
            ).toUtc().toIso8601String(),
            'duration': int.parse(duration),
            'category': category,
          });
        },
        child: const Text('Schedule'),
      ),
    ],
  );
}

class _AttendanceDialog extends StatefulWidget {
  final List<dynamic> classes, students;
  const _AttendanceDialog({required this.classes, required this.students});
  @override
  State<_AttendanceDialog> createState() => _AttendanceDialogState();
}

class _AttendanceDialogState extends State<_AttendanceDialog> {
  int? session, student;
  bool present = true;
  final form = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record attendance'),
    content: SizedBox(
      width: 400,
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              items: widget.classes
                  .map(
                    (c) => DropdownMenuItem(
                      value: c['id'] as int,
                      child: Text(c['title'] as String),
                    ),
                  )
                  .toList(),
              validator: (v) => v == null ? 'Select a class.' : null,
              onChanged: (v) => session = v,
              decoration: const InputDecoration(labelText: 'Class'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              items: widget.students
                  .map(
                    (s) => DropdownMenuItem(
                      value: s['id'] as int,
                      child: Text(s['name'] as String),
                    ),
                  )
                  .toList(),
              validator: (v) => v == null ? 'Select a student.' : null,
              onChanged: (v) => student = v,
              decoration: const InputDecoration(labelText: 'Enrolled student'),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Present'),
              value: present,
              onChanged: (v) => setState(() => present = v),
            ),
          ],
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
          if (form.currentState!.validate()) {
            Navigator.pop(context, {
              'session': session,
              'student': student,
              'present': present,
            });
          }
        },
        child: const Text('Save'),
      ),
    ],
  );
}
