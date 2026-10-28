import 'whatsapp_reminders.dart';
import 'student_records.dart';
import 'recurring_schedule.dart';
import 'conversation_review.dart';
import 'academy_design.dart';
import 'classroom.dart';
import 'class_chat.dart';
import 'quran_reader.dart';
import 'message_events.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _green = Color(0xFF145B45);
const _cream = Color(0xFFF8F7F2);
const _muted = Color(0xFF77867D);
// Only explicitly packaged native builds may use a loopback API in release.
const desktopLocalApi = !kIsWeb && bool.fromEnvironment('DESKTOP_LOCAL_API');
// Local debug sessions use the local API. Published builds require an explicit
// HTTPS backend URL and never point visitors at their own localhost.
const academyApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: kDebugMode ? 'http://127.0.0.1:8000' : '',
);

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
            ((kDebugMode || desktopLocalApi) &&
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
  final bool realtime;
  const LivePortal({super.key, this.api, this.realtime = true});
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
  String classTab = 'Upcoming', resourceQuery = '';
  DateTime calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? attendanceDay;
  final loginForm = GlobalKey<FormState>();
  final compose = TextEditingController();
  MessageEvents? chatEvents;
  final sessionActive = ValueNotifier<bool>(false);
  bool chatConnected = false,
      refreshingChat = false,
      pendingChatRefresh = false;
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
    'Weekly schedule',
    'Student records',
    if (role == 'admin') ...['Chat review', 'Reminder delivery'],
    'WhatsApp reminders',
    'Progress',
    'Attendance',
    'Quran',
    'Resources',
    'Homework',
    'Messages',
    if (role == 'parent') 'Feedback',
    if (role == 'admin') 'Reports',
    'Account',
  ];
  @override
  void dispose() {
    chatEvents?.close();
    sessionActive.dispose();
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
          if (api.token == null) {
            user = null;
            clearPrivateState();
          }
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
      clearPrivateState();
      api.token = data['token'] as String;
      password = '';
      user = Map<String, dynamic>.from(data['user'] as Map);
      sessionActive.value = true;
      await refresh();
      startChat();
    });
  }

  void startChat() {
    chatEvents?.close();
    if (!widget.realtime || api.token == null) return;
    chatEvents = MessageEvents(
      baseUrl: api.baseUrl,
      token: api.token!,
      onChanged: refreshChat,
      onConnected: (value) {
        if (mounted) setState(() => chatConnected = value);
      },
      onExpired: () {
        if (mounted) {
          setState(() {
            api.token = null;
            user = null;
            clearPrivateState();
            error = 'Your session expired. Please sign in again.';
          });
        }
      },
    )..connect();
  }

  void clearPrivateState() {
    sessionActive.value = false;
    chatEvents?.close();
    chatConnected = false;
    pendingChatRefresh = false;
    users = [];
    classes = [];
    attendance = [];
    homework = [];
    resources = [];
    contacts = [];
    progress = [];
    messages = [];
    report = {};
    studentId = null;
    contactId = null;
    compose.clear();
    page = 'Overview';
    classTab = 'Upcoming';
    resourceQuery = '';
    attendanceDay = null;
  }

  Future<void> refreshChat() async {
    if (user == null || api.token == null) return;
    if (refreshingChat) {
      pendingChatRefresh = true;
      return;
    }
    refreshingChat = true;
    final current = contactId, owner = api.token;
    try {
      final data = current == null
          ? null
          : await api.call('/messages/$current');
      if (mounted &&
          api.token == owner &&
          current == contactId &&
          data != null) {
        setState(() => messages = data as List);
      }
    } catch (_) {
      if (api.token == null && mounted) {
        setState(() {
          user = null;
          clearPrivateState();
          error = 'Please sign in again.';
        });
      }
    } finally {
      refreshingChat = false;
      if (pendingChatRefresh) {
        pendingChatRefresh = false;
        refreshChat();
      }
    }
  }

  Future<void> refresh() async {
    final owner = api.token;
    final results = await Future.wait([
      api.call('/users'),
      api.call('/classes'),
      api.call('/attendance'),
      api.call('/homework'),
      api.call('/resources'),
      api.call('/contacts'),
    ]);
    final nextUsers = results[0] as List, nextContacts = results[5] as List;
    final children = nextUsers.where((u) => u['role'] == 'student').toList();
    final nextStudent = children.any((u) => u['id'] == studentId)
        ? studentId
        : children.isEmpty
        ? null
        : children.first['id'] as int;
    final nextContact = nextContacts.any((c) => c['id'] == contactId)
        ? contactId
        : nextContacts.isEmpty
        ? null
        : nextContacts.first['id'] as int;
    final nextProgress = nextStudent == null
        ? []
        : await api.call('/students/$nextStudent/progress') as List;
    final nextMessages = nextContact == null
        ? []
        : await api.call('/messages/$nextContact') as List;
    final nextReport = role == 'admin'
        ? Map<String, dynamic>.from(await api.call('/admin/reports') as Map)
        : <String, dynamic>{};
    if (!mounted || owner != api.token || user == null) return;
    setState(() {
      users = nextUsers;
      classes = results[1] as List;
      attendance = results[2] as List;
      homework = results[3] as List;
      resources = results[4] as List;
      contacts = nextContacts;
      progress = nextProgress;
      messages = nextMessages;
      report = nextReport;
      studentId = nextStudent;
      contactId = nextContact;
    });
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
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Color(0xFFE4EADF)),
    ),
    child: Padding(padding: const EdgeInsets.all(20), child: child),
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
  void navigate(String next) => setState(() => page = next);
  IconData pageIcon(String value) => switch (value) {
    'Overview' => Icons.home_outlined,
    'People' => Icons.groups_outlined,
    'Assignments' => Icons.family_restroom_outlined,
    'Classes' => Icons.calendar_month_outlined,
    'Weekly schedule' => Icons.repeat,
    'Student records' => Icons.summarize_outlined,
    'Chat review' => Icons.forum_outlined,
    'WhatsApp reminders' => Icons.notifications_active_outlined,
    'Reminder delivery' => Icons.send_to_mobile_outlined,
    'Progress' => Icons.insights_outlined,
    'Attendance' => Icons.event_available_outlined,
    'Quran' => Icons.menu_book_outlined,
    'Resources' => Icons.library_books_outlined,
    'Homework' => Icons.assignment_outlined,
    'Messages' => Icons.chat_bubble_outline,
    'Reports' => Icons.bar_chart_outlined,
    'Feedback' => Icons.star_outline,
    _ => Icons.person_outline,
  };
  String get portalTitle => switch (role) {
    'admin' => 'Admin Portal',
    'teacher' => 'Teacher Portal',
    'parent' => 'Parent Portal',
    _ => 'Student Portal',
  };
  Future<void> signOut() => execute(() async {
    await api.call('/auth/logout', method: 'POST');
    clearPrivateState();
    api.token = null;
    user = null;
    password = '';
  });
  @override
  Widget build(BuildContext context) {
    if (user == null) return loginPage();
    final wide = MediaQuery.sizeOf(context).width > 900;
    const bottomPages = [
      'Overview',
      'Classes',
      'Progress',
      'Messages',
      'Account',
    ];
    return Scaffold(
      backgroundColor: academyIvory,
      appBar: AppBar(
        backgroundColor: academyIvory,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 78,
        title: AcademyBrand(subtitle: portalTitle),
        actions: [
          IconButton(
            tooltip: 'Refresh academy records',
            onPressed: busy ? null : () => execute(refresh),
            icon: const Icon(Icons.refresh, size: 21),
          ),
          IconButton(
            tooltip: 'Messages',
            onPressed: () => navigate('Messages'),
            icon: const Badge(
              smallSize: 6,
              backgroundColor: academyGold,
              child: Icon(Icons.notifications_none_rounded),
            ),
          ),
          if (wide)
            TextButton(
              onPressed: busy ? null : signOut,
              child: const Text('Sign out'),
            ),
          const SizedBox(width: 12),
        ],
      ),
      drawer: wide ? null : Drawer(child: navigation()),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: bottomPages.contains(page)
                  ? bottomPages.indexOf(page)
                  : 0,
              onDestinationSelected: (index) => navigate(bottomPages[index]),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: 'Classes',
                ),
                NavigationDestination(
                  icon: Icon(Icons.insights_outlined),
                  label: 'Progress',
                ),
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  label: 'Messages',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  label: 'Profile',
                ),
              ],
            ),
      body: Row(
        children: [
          if (wide) SizedBox(width: 230, child: navigation()),
          Expanded(
            child: AcademyBackdrop(
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
                      padding: EdgeInsets.all(wide ? 32 : 18),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1120),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (page != 'Overview')
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 18),
                                  child: Row(
                                    children: [
                                      AcademyAvatar(
                                        name: user!['name'] as String,
                                        radius: 17,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          user!['name'] as String,
                                          style: const TextStyle(
                                            color: _muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              content(),
                              const SizedBox(height: 26),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
          child: AcademyBrand(subtitle: portalTitle),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'YOUR ACADEMY',
            style: TextStyle(fontSize: 10, letterSpacing: 1.8, color: _muted),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: pages
                .map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      selected: page == p,
                      selectedColor: _green,
                      selectedTileColor: const Color(0xFFEAF1E9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(pageIcon(p), size: 21),
                      title: Text(
                        p == 'Overview' ? 'Home' : p,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () {
                        navigate(p);
                        if (MediaQuery.sizeOf(context).width <= 900) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ListTile(
            leading: AcademyAvatar(name: user!['name'] as String, radius: 18),
            title: Text(
              user!['name'] as String,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(portalTitle, style: const TextStyle(fontSize: 10)),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.logout, size: 20),
          title: const Text('Sign out'),
          onTap: busy ? null : signOut,
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
    body: AcademyBackdrop(
      child: Center(
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
                      'Login to your account · Learn. Practice. Grow.',
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
    'Student records' => StudentRecords(
      key: ValueKey(studentId),
      initialStudentId: studentId,
      students: students,
      fetch: (path) => api.call(path),
    ),
    'Weekly schedule' => RecurringSchedules(
      fetch: (path) => api.call(path),
      save: (path, data) async {
        await api.call(path, method: 'POST', body: data);
        await execute(refresh);
      },
      students: students,
      teachers: role == 'teacher' ? [user!] : teachers,
      editor: editor,
    ),
    'Chat review' => ConversationReview(fetch: (path) => api.call(path)),
    'WhatsApp reminders' => WhatsAppReminderSettings(
      fetch: (path) => api.call(path),
      save: (path, body) async {
        await api.call(path, method: 'PUT', body: body);
      },
    ),
    'Reminder delivery' => ReminderDelivery(fetch: (path) => api.call(path)),
    'Progress' => progressPage(),
    'Attendance' => attendancePage(),
    'Resources' => resourcePage(),
    'Quran' => QuranReader(fetch: (path) => api.call(path)),
    'Homework' => homeworkPage(),
    'Messages' => messagePage(),
    'Feedback' => feedbackPage(),
    'Reports' => reportPage(),
    'Account' => accountPage(),
    _ => overview(),
  };
  List<dynamic> get upcomingClasses {
    final now = DateTime.now();
    final upcoming = classes.where((c) {
      final raw = c['starts_at'] as String;
      final start = DateTime.tryParse(
        raw.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(raw)
            ? raw
            : '${raw}Z',
      );
      return start != null &&
          start
              .add(Duration(minutes: (c['duration'] as num?)?.toInt() ?? 30))
              .isAfter(now);
    }).toList();
    upcoming.sort(
      (a, b) => (a['starts_at'] as String).compareTo(b['starts_at'] as String),
    );
    return upcoming;
  }

  Widget sectionTitle(String title, {String? destination}) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              color: academyInk,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (destination != null)
          TextButton(
            onPressed: () => navigate(destination),
            child: const Text('View all', style: TextStyle(fontSize: 11)),
          ),
      ],
    ),
  );
  Widget overview() {
    final upcoming = upcomingClasses;
    final present = attendance.where((a) => a['present'] == true).length;
    final rate = attendance.isEmpty
        ? '—'
        : '${(present * 100 / attendance.length).round()}%';
    final pending = homework.where((h) => h['completed'] == false).length;
    final stats = role == 'admin'
        ? [
            ('Students', '${students.length}', Icons.school_outlined, _green),
            (
              'Teachers',
              '${teachers.length}',
              Icons.person_outline,
              const Color(0xFF7661AD),
            ),
            (
              'Classes',
              '${classes.length}',
              Icons.calendar_month_outlined,
              const Color(0xFFC88738),
            ),
            ('Attendance', rate, Icons.event_available_outlined, _green),
          ]
        : [
            (
              role == 'parent'
                  ? 'My children'
                  : role == 'teacher'
                  ? 'My students'
                  : 'My classes',
              '${role == 'student' ? classes.length : students.length}',
              Icons.school_outlined,
              _green,
            ),
            (
              'Upcoming classes',
              '${upcoming.length}',
              Icons.calendar_month_outlined,
              const Color(0xFFC88738),
            ),
            ('Attendance', rate, Icons.event_available_outlined, _green),
            (
              'Resources',
              '${resources.length}',
              Icons.library_books_outlined,
              const Color(0xFF547DB8),
            ),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AcademyAvatar(name: user!['name'] as String),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Assalamu Alaikum,',
                    style: TextStyle(fontSize: 11, color: _muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user!['name'] as String,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: academyInk,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          MaterialLocalizations.of(context).formatFullDate(DateTime.now()),
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 10, color: _muted),
        ),
        const SizedBox(height: 22),
        if (role == 'student' || role == 'parent') nextLessonBanner(upcoming),
        LayoutBuilder(
          builder: (context, c) {
            final count = c.maxWidth > 700 ? 4 : 2;
            final width = (c.maxWidth - (count - 1) * 12) / count;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: stats
                  .map(
                    (s) => SizedBox(
                      width: width,
                      child: dashboardStat(s.$1, s.$2, s.$3, s.$4),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        if (role == 'parent') ...[
          sectionTitle('My children'),
          if (students.isEmpty)
            blank('No children are linked to your account yet.'),
          ...students.map(
            (child) => box(
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: AcademyAvatar(
                  name: child['name'] as String,
                  radius: 20,
                ),
                title: Text(
                  child['name'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(child['level'] as String? ?? 'Student'),
                trailing: const Icon(Icons.chevron_right, size: 19),
                onTap: () => execute(() async {
                  studentId = child['id'] as int;
                  progress =
                      await api.call('/students/$studentId/progress') as List;
                  page = 'Student records';
                }),
              ),
            ),
          ),
        ],
        if (role == 'student' || role == 'parent') ...[
          sectionTitle(
            role == 'parent' ? "Child’s progress" : 'My Quran progress',
            destination: 'Progress',
          ),
          if (progress.isEmpty)
            blank('Your teacher-recorded Quran progress will appear here.'),
          ...progress.take(2).map(progressCard),
        ],
        sectionTitle('Quick actions'),
        box(
          Wrap(
            alignment: WrapAlignment.spaceAround,
            runSpacing: 18,
            children: [
              if (role == 'admin')
                AcademyQuickAction(
                  label: 'Add student',
                  icon: Icons.person_add_alt_1_outlined,
                  onTap: busy ? null : () => addAccount(accountRole: 'student'),
                ),
              if (role == 'admin')
                AcademyQuickAction(
                  label: 'Add teacher',
                  icon: Icons.school_outlined,
                  color: const Color(0xFF547DB8),
                  onTap: busy ? null : () => addAccount(accountRole: 'teacher'),
                ),
              if (editor)
                AcademyQuickAction(
                  label: 'Create class',
                  icon: Icons.calendar_month_outlined,
                  color: const Color(0xFF547DB8),
                  onTap: busy ? null : scheduleClass,
                ),
              if (!editor)
                AcademyQuickAction(
                  label: 'My classes',
                  icon: Icons.calendar_month_outlined,
                  onTap: () => navigate('Classes'),
                ),
              if (role != 'admin')
                AcademyQuickAction(
                  label: 'Quran',
                  icon: Icons.menu_book_outlined,
                  onTap: () => navigate('Quran'),
                ),
              AcademyQuickAction(
                label: role == 'admin' ? 'Reports' : 'Homework',
                icon: Icons.assignment_outlined,
                color: const Color(0xFFC88738),
                onTap: () => navigate(role == 'admin' ? 'Reports' : 'Homework'),
              ),
              if (role != 'admin')
                AcademyQuickAction(
                  label: 'Messages',
                  icon: Icons.chat_bubble_outline,
                  onTap: () => navigate('Messages'),
                ),
            ],
          ),
        ),
        sectionTitle(
          role == 'teacher' ? 'Your teaching schedule' : 'Your next classes',
          destination: 'Classes',
        ),
        if (upcoming.isEmpty)
          blank(
            'No classes scheduled yet. Your teacher or administrator can add your next lesson.',
          ),
        ...upcoming.take(3).map(classCard),
        sectionTitle('Recent homework', destination: 'Homework'),
        if (homework.isEmpty) blank('No homework assigned yet.'),
        ...homework
            .take(3)
            .map(
              (h) => box(
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    h['completed'] == true
                        ? Icons.task_alt
                        : Icons.assignment_outlined,
                    color: h['completed'] == true
                        ? _green
                        : const Color(0xFFC88738),
                  ),
                  title: Text(
                    h['title'] as String,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    h['completed'] == true
                        ? 'Completed'
                        : '$pending assignment(s) pending',
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                  onTap: () => navigate('Homework'),
                ),
              ),
            ),
      ],
    );
  }

  Widget dashboardStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .95),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFEEEFE7)),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(label, style: const TextStyle(fontSize: 10, color: _muted)),
            ],
          ),
        ),
      ],
    ),
  );
  Widget nextLessonBanner(List<dynamic> upcoming) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(23),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF123E30), Color(0xFF1E7859)],
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'YOUR NEXT CLASS',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.3,
                  color: Color(0xFFCADCCD),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                upcoming.isEmpty
                    ? 'Your journey starts here'
                    : upcoming.first['title'] as String,
                style: const TextStyle(
                  fontSize: 20,
                  fontFamily: 'CormorantGaramond',
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Learn. Practice. Grow.',
                style: TextStyle(fontSize: 11, color: Color(0xFFE5D5AC)),
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE8F3E8),
                  foregroundColor: _green,
                ),
                onPressed: () => navigate('Classes'),
                child: const Text('View classes'),
              ),
            ],
          ),
        ),
        const Icon(Icons.mosque_outlined, color: Color(0xFF89B49B), size: 68),
      ],
    ),
  );
  Widget progressCard(dynamic p) => box(
    Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p['surah'] as String,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                p['percent'] == 100 ? 'Completed' : 'In progress',
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: (p['percent'] as num) / 100,
                minHeight: 5,
                color: _green,
                backgroundColor: const Color(0xFFE6EEE5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 22),
        SizedBox(
          width: 47,
          height: 47,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: (p['percent'] as num) / 100,
                  strokeWidth: 3,
                  color: _green,
                  backgroundColor: const Color(0xFFE6EEE5),
                ),
              ),
              Text(
                '${p['percent']}%',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
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

  Future<void> addAccount({String? accountRole}) async {
    final data = await formDialog(
      'Create academy account',
      [
        ('Name', '', false),
        ('Email', '', false),
        ('Initial password', '', true),
        ('Level / specialty', 'Level 1', false),
      ],
      options: [
        ?accountRole,
        ...[
          'student',
          'teacher',
          'parent',
          'admin',
        ].where((r) => r != accountRole),
      ],
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
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => navigate('Weekly schedule'),
          icon: const Icon(Icons.repeat),
          label: const Text('Set once · Weekly schedule'),
        ),
      ),
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
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'Upcoming', label: Text('Upcoming')),
          ButtonSegment(value: 'Past', label: Text('Past')),
        ],
        selected: {classTab},
        onSelectionChanged: (v) => setState(() => classTab = v.first),
      ),
      const SizedBox(height: 20),
      if (visibleClasses.isEmpty)
        blank(
          classTab == 'Upcoming'
              ? 'No upcoming classes have been scheduled.'
              : 'No past classes yet.',
        ),
      ...visibleClasses.map(classCard),
    ],
  );
  List<dynamic> get visibleClasses => classTab == 'Upcoming'
      ? upcomingClasses
      : classes
            .where((c) => !upcomingClasses.any((u) => u['id'] == c['id']))
            .toList();
  DateTime classDate(dynamic c) {
    final raw = c['starts_at'] as String;
    return DateTime.parse(
      raw.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(raw)
          ? raw
          : '${raw}Z',
    ).toLocal();
  }

  Widget classCard(dynamic c) {
    final date = classDate(c);
    return box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF4EC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.calendar_month_outlined,
                  color: _green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  c['title'] as String,
                  style: const TextStyle(
                    fontFamily: 'CormorantGaramond',
                    fontSize: 22,
                    color: _green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                            sessionActive: sessionActive,
                            chat: ClassChat(
                              baseUrl: api.baseUrl,
                              token: api.token!,
                              fetch: (path) async {
                                try {
                                  return await api.call(path);
                                } finally {
                                  if (api.token == null) {
                                    sessionActive.value = false;
                                  }
                                }
                              },
                              send: (recipient, text) async {
                                try {
                                  await api.call(
                                    '/messages',
                                    method: 'POST',
                                    body: {
                                      'recipient_id': recipient,
                                      'text': text,
                                    },
                                  );
                                } finally {
                                  if (api.token == null) {
                                    sessionActive.value = false;
                                  }
                                }
                              },
                            ),
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
        (p) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            progressCard(p),
            if ((p['notes'] as String? ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
                child: Text(
                  p['notes'] as String,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
              ),
          ],
        ),
      ),
    ],
  );
  Widget attendancePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading('Attendance', 'A record of each lesson attended.'),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => navigate('Student records'),
          icon: const Icon(Icons.bar_chart_outlined),
          label: const Text('Attendance charts & student summary'),
        ),
      ),
      attendanceCalendar(),
      if (editor && classes.isNotEmpty && students.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: busy ? null : markAttendance,
            child: const Text('Record attendance'),
          ),
        ),
      const SizedBox(height: 20),
      if (visibleAttendance.isEmpty)
        blank('No attendance recorded for this selection.'),
      ...visibleAttendance.map(
        (a) => box(
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(className(a['session_id'])),
            subtitle: Text(person(a['student_id'])),
            leading: Icon(
              a['present'] == true
                  ? Icons.event_available_outlined
                  : Icons.event_busy_outlined,
              color: a['present'] == true ? _green : Colors.redAccent,
            ),
            trailing: Chip(
              backgroundColor: a['present'] == true
                  ? const Color(0xFFE8F5EA)
                  : const Color(0xFFFFEFEB),
              side: BorderSide.none,
              label: Text(
                a['present'] == true ? 'Present' : 'Absent',
                style: TextStyle(
                  color: a['present'] == true ? _green : Colors.red,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
  List<dynamic> get visibleAttendance => attendanceDay == null
      ? attendance
      : attendance.where((a) {
          final session = classes
              .where((c) => c['id'] == a['session_id'])
              .firstOrNull;
          if (session == null) return false;
          return DateUtils.isSameDay(classDate(session), attendanceDay);
        }).toList();
  Widget attendanceCalendar() {
    final first = DateTime(calendarMonth.year, calendarMonth.month);
    final days = DateUtils.getDaysInMonth(first.year, first.month);
    final offset = first.weekday % 7;
    final classDays = classes.map(classDate).toList();
    return box(
      Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => setState(() {
                  calendarMonth = DateTime(first.year, first.month - 1);
                  attendanceDay = null;
                }),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  MaterialLocalizations.of(context).formatMonthYear(first),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: () => setState(() {
                  calendarMonth = DateTime(first.year, first.month + 1);
                  attendanceDay = null;
                }),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                .map(
                  (day) => Expanded(
                    child: Text(
                      day,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10, color: _muted),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 40,
            ),
            itemCount: offset + days,
            itemBuilder: (context, index) {
              if (index < offset) return const SizedBox.shrink();
              final day = DateTime(first.year, first.month, index - offset + 1);
              final selected = DateUtils.isSameDay(day, attendanceDay);
              final hasClass = classDays.any(
                (d) => DateUtils.isSameDay(d, day),
              );
              return Center(
                child: SizedBox(
                  width: 35,
                  height: 35,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: selected ? _green : Colors.transparent,
                      foregroundColor: selected ? Colors.white : academyInk,
                      shape: CircleBorder(
                        side: BorderSide(
                          color: DateUtils.isSameDay(day, DateTime.now())
                              ? academyGold
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    onPressed: () =>
                        setState(() => attendanceDay = selected ? null : day),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${day.day}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        if (hasClass)
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: selected ? Colors.white : _green,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          TextButton(
            onPressed: () => setState(() => attendanceDay = null),
            child: Text(
              attendanceDay == null
                  ? 'Showing all records'
                  : 'Show all records',
            ),
          ),
        ],
      ),
    );
  }

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
      TextField(
        onChanged: (v) => setState(() => resourceQuery = v),
        decoration: const InputDecoration(
          hintText: 'Search learning resources…',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      const SizedBox(height: 20),
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
      ...resources
          .where(
            (r) => (r['title'] as String).toLowerCase().contains(
              resourceQuery.toLowerCase(),
            ),
          )
          .map(
            (r) => box(
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECF3ED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.description_outlined, color: _green),
                ),
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
  Widget contactDirectory() => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: contacts
          .map(
            (c) => ActionChip(
              avatar: Icon(
                c['role'] == 'admin'
                    ? Icons.admin_panel_settings_outlined
                    : c['role'] == 'parent'
                    ? Icons.family_restroom
                    : c['role'] == 'teacher'
                    ? Icons.school_outlined
                    : Icons.person_outline,
                size: 16,
              ),
              label: Text(
                '${c['name']} · ${c['role']}',
                style: const TextStyle(fontSize: 11),
              ),
              onPressed: busy
                  ? null
                  : () => execute(() async {
                      contactId = c['id'] as int;
                      messages = await api.call('/messages/$contactId') as List;
                    }),
            ),
          )
          .toList(),
    ),
  );
  Widget messagePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Messages',
        'Chat with your linked students, their parents, teachers, and academy admin.',
      ),
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(
          supervisionNotice,
          style: TextStyle(fontSize: 11, color: _muted),
        ),
      ),
      contactDirectory(),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          chatConnected
              ? 'Live chat connected'
              : 'Reconnecting live chat… Refresh is also available.',
          style: const TextStyle(fontSize: 11, color: _muted),
        ),
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
      heading('My profile', 'Your academy profile and account security.'),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => navigate('WhatsApp reminders'),
          icon: const Icon(Icons.notifications_active_outlined),
          label: const Text('Set WhatsApp class reminders'),
        ),
      ),
      box(
        Column(
          children: [
            AcademyAvatar(name: user!['name'] as String, radius: 44),
            const SizedBox(height: 14),
            Text(
              user!['name'] as String,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(portalTitle, style: const TextStyle(color: _muted)),
          ],
        ),
      ),
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
                          clearPrivateState();
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
  Widget stat(String label, String value) => SizedBox(
    width: 210,
    child: dashboardStat(label, value, pageIcon(label), _green),
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
