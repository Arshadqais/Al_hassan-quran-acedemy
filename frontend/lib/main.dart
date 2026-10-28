import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'live_portal.dart';
import 'academy_design.dart';
import 'install_help.dart';

const green = Color(0xFF145B45);
const dark = Color(0xFF143B30);
const gold = Color(0xFFBA9758);
const cream = academyIvory;
const muted = Color(0xFF77867D);
const pale = Color(0xFFEAF1E9);
void main() => runApp(const AcademyApp());

class AcademyApp extends StatelessWidget {
  const AcademyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Al Hassan | Online Quran Academy',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: academyIvory,
        foregroundColor: academyInk,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: pale,
        height: 70,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 10, color: dark),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFECEDE5),
        thickness: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: green,
        linearTrackColor: pale,
        borderRadius: BorderRadius.all(Radius.circular(9)),
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: green,
        primary: green,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: cream,
      fontFamily: 'Manrope',
      fontFamilyFallback: const ['NotoNaskhArabic'],
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: dark, height: 1.5),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cream,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 19),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: green,
          side: const BorderSide(color: Color(0xFFD4DED3)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    ),
    home: const AcademyShell(),
  );
}

class Person {
  String name, email, level;
  Person(this.name, this.email, this.level);
}

class Lesson {
  String name, teacher, time, category;
  Lesson(this.name, this.teacher, this.time, this.category);
}

class AcademyShell extends StatefulWidget {
  const AcademyShell({super.key});
  @override
  State<AcademyShell> createState() => _AcademyShellState();
}

class _AcademyShellState extends State<AcademyShell> {
  String role = 'Student',
      page = 'Overview',
      search = '',
      resourceFilter = 'All';
  bool entered = false, rolePicker = false;
  int selectedChild = 0;
  final students = [
    Person('Ali Hassan', 'ali@example.test', 'Level 1'),
    Person('Fatima Khan', 'fatima@example.test', 'Level 2'),
    Person('Omar Ahmed', 'omar@example.test', 'Level 1'),
    Person('Aisha Malik', 'aisha@example.test', 'Level 3'),
  ];
  final teachers = [
    Person('Ustadh Ahmed', 'ahmed@example.test', 'Tajweed & recitation'),
    Person('Ustadha Maryam', 'maryam@example.test', 'Quran memorization'),
  ];
  final lessons = [
    Lesson(
      'Quran recitation',
      'Ustadh Ahmed',
      '09:00 AM',
      'Individual · 30 min',
    ),
    Lesson('Tajweed essentials', 'Ustadh Ahmed', '10:00 AM', 'Group · 60 min'),
    Lesson(
      'Quran memorization',
      'Ustadha Maryam',
      '02:00 PM',
      'Group · 45 min',
    ),
  ];
  final attendance = <String, bool>{
    'Quran recitation': true,
    'Tajweed essentials': true,
    'Quran memorization': false,
    'Revision & practice': true,
  };
  final messages = <String>[
    'Assalamu Alaikum! Please revise verses 1–5 of Surah Al-Baqarah before our next class.',
  ];
  final homeworkDone = <String>{};
  String conversation = 'Ustadh Ahmed';
  final composer = TextEditingController();
  final searchController = TextEditingController();
  final feedback = TextEditingController();
  int rating = 5;
  final progress = <String, double>{
    'Al-Fatiha': 1,
    'Al-Baqarah': .65,
    'Aal-E-Imran': .0,
    'An-Nisa': .0,
    "Al-Ma’idah": .0,
  };
  List<String> get menu => [
    'Overview',
    if (role == 'Admin') ...['Students', 'Teachers'],
    if (role == 'Parent') 'My children',
    'My classes',
    'Quran progress',
    'Attendance',
    'Resources',
    'Homework',
    'Messages',
    if (role == 'Parent') 'Feedback',
    if (role == 'Admin') 'Reports',
    'Settings',
  ];
  String get name => switch (role) {
    'Admin' => 'Academy Admin',
    'Teacher' => 'Ustadh Ahmed',
    'Parent' => 'Sara Khan',
    _ => 'Ali Hassan',
  };
  String get firstName => switch (role) {
    'Admin' => 'Admin',
    'Teacher' => 'Ustadh Ahmed',
    'Parent' => 'Sara',
    _ => 'Ali',
  };
  void go(String next) => setState(() {
    page = next;
    search = '';
    searchController.clear();
  });
  void toast(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
  @override
  void dispose() {
    composer.dispose();
    searchController.dispose();
    feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    if (!entered) {
      return Scaffold(
        body: AcademyBackdrop(
          child: SafeArea(child: rolePicker ? chooseRole() : landing()),
        ),
      );
    }
    return Scaffold(
      drawer: wide ? null : Drawer(child: sidebar()),
      body: SafeArea(
        child: Row(
          children: [
            if (wide) SizedBox(width: 238, child: sidebar()),
            Expanded(
              child: Column(
                children: [
                  header(wide),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(wide ? 32 : 18),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1320),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              demoBanner(),
                              const SizedBox(height: 24),
                              pageContent(wide),
                              const SizedBox(height: 28),
                              footer(),
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
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex:
                  [
                    'Overview',
                    'My classes',
                    'Messages',
                    'Settings',
                  ].contains(page)
                  ? [
                      'Overview',
                      'My classes',
                      'Messages',
                      'Settings',
                    ].indexOf(page)
                  : 0,
              onDestinationSelected: (i) =>
                  go(['Overview', 'My classes', 'Messages', 'Settings'][i]),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.grid_view_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: 'Classes',
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
    );
  }

  Widget brand({bool small = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: small ? 38 : 46,
        height: small ? 38 : 46,
        decoration: BoxDecoration(
          color: pale,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.mosque_outlined, color: green, size: small ? 26 : 32),
      ),
      const SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AL HASSAN',
            style: TextStyle(
              fontFamily: 'CormorantGaramond',
              fontSize: small ? 14 : 20,
              fontWeight: FontWeight.w700,
              letterSpacing: small ? 1.0 : 1.4,
              color: dark,
            ),
          ),
          Text(
            'ONLINE QURAN ACADEMY',
            style: TextStyle(
              fontSize: small ? 6 : 8,
              letterSpacing: small ? 1.0 : 1.8,
              color: muted,
            ),
          ),
        ],
      ),
    ],
  );
  Widget landing() => LayoutBuilder(
    builder: (context, c) {
      final desktop = c.maxWidth > 850;
      final welcome = Column(
        crossAxisAlignment: desktop
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          pill('LEARN · PRACTICE · GROW', gold),
          const SizedBox(height: 22),
          Text(
            'Welcome to\nAl Hassan Online\nQuran Academy',
            textAlign: desktop ? TextAlign.left : TextAlign.center,
            style: TextStyle(
              fontFamily: 'CormorantGaramond',
              fontSize: desktop ? 57 : 35,
              height: 1.08,
              color: dark,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Learn Quran with qualified teachers,\nfrom anywhere in the world.',
            textAlign: desktop ? TextAlign.left : TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.8, color: muted),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: 350,
            child: FilledButton(
              onPressed: signIn,
              child: const Text('Academy sign in'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 350,
            child: OutlinedButton(
              onPressed: () => setState(() => rolePicker = true),
              child: Text(desktop ? 'Explore the academy' : 'Explore'),
            ),
          ),
          const SizedBox(height: 18),
          if (kIsWeb)
            TextButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AcademyInstallHelp(),
              ),
              icon: const Icon(Icons.install_mobile_outlined),
              label: const Text('Install the academy app'),
            ),
          const Text(
            'A place for students, teachers, and families.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
      );
      return SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: desktop ? 48 : 22,
                    vertical: 22,
                  ),
                  child: Row(
                    children: [
                      brand(small: !desktop),
                      const Spacer(),
                      IconButton(
                        onPressed: showAbout,
                        tooltip: 'About the academy',
                        icon: const Icon(Icons.info_outline, color: green),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    desktop ? 48 : 26,
                    desktop ? 20 : 0,
                    desktop ? 48 : 26,
                    35,
                  ),
                  child: desktop
                      ? Row(
                          children: [
                            const Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(right: 68),
                                child: AcademyIllustration(),
                              ),
                            ),
                            Expanded(child: welcome),
                          ],
                        )
                      : Column(
                          children: [
                            const SizedBox(
                              width: 240,
                              child: AcademyIllustration(),
                            ),
                            const SizedBox(height: 26),
                            welcome,
                          ],
                        ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: Text(
                    'Quran recitation  ·  Tajweed  ·  Memorization',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  void signIn() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const LivePortal()));
  void showAbout() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Learning with Al Hassan'),
      content: const SingleChildScrollView(
        child: Text(
          'Our academy experience brings Quran recitation, Tajweed, memorization, and Islamic learning into one welcoming space.\n\nExplore the student, parent, teacher, and administrator portals to see schedules, progress, attendance, and learning resources.\n\nThis is an interactive demonstration using fictional records. Enrollment, real accounts, live messaging, and video lessons will be available after the academy backend is connected.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(c);
            setState(() => rolePicker = true);
          },
          child: const Text('Explore portals'),
        ),
      ],
    ),
  );
  void enter(String r) => setState(() {
    role = r;
    entered = true;
    rolePicker = false;
    page = 'Overview';
    search = '';
    searchController.clear();
  });
  Widget chooseRole() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 500,
        child: Column(
          children: [
            brand(),
            const SizedBox(height: 44),
            const Text(
              'Assalamu Alaikum',
              style: TextStyle(
                fontFamily: 'CormorantGaramond',
                fontSize: 36,
                color: dark,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Select your role to explore the demo',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 30),
            for (final r in ['Admin', 'Teacher', 'Student', 'Parent'])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () => enter(r),
                  borderRadius: BorderRadius.circular(14),
                  child: panel(
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: pale,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            roleIcon(r),
                            color: const Color(0xFF89703D),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r == 'Admin' ? 'Admin / Principal' : r,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                roleDescription(r),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward, size: 18, color: green),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Interactive demo · fictional records · no account required',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: muted),
            ),
            TextButton(
              onPressed: signIn,
              child: const Text('Academy sign in →'),
            ),
            TextButton(
              onPressed: () => setState(() => rolePicker = false),
              child: const Text('← Back to the academy'),
            ),
          ],
        ),
      ),
    ),
  );
  Widget sidebar() => Material(
    color: Colors.white,
    child: Container(
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFFE9EDE5))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(23, 30, 12, 28),
            child: brand(small: true),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Text(
              '$role PORTAL'.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                letterSpacing: 2,
                color: muted,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final item in menu)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: ListTile(
                      dense: true,
                      selected: page == item,
                      selectedTileColor: pale,
                      selectedColor: green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      leading: Icon(navIcon(item), size: 20),
                      title: Text(
                        item,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: page == item
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      onTap: () {
                        go(item);
                        if (MediaQuery.sizeOf(context).width < 1050) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cream,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.spa_outlined, color: gold),
                  const SizedBox(height: 10),
                  const Text(
                    'A little every day.',
                    style: TextStyle(
                      fontFamily: 'CormorantGaramond',
                      fontSize: 17,
                      color: dark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '“And say, My Lord, increase me in knowledge.”',
                    style: TextStyle(fontSize: 11, color: muted, height: 1.7),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'QURAN 20:114',
                    style: TextStyle(
                      color: gold,
                      fontSize: 8,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout, size: 18),
            title: const Text('Leave demo', style: TextStyle(fontSize: 12)),
            onTap: () => setState(() => entered = false),
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
  Widget header(bool wide) => Container(
    height: 82,
    padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE9EDE5))),
    ),
    child: Row(
      children: [
        if (!wide)
          Builder(
            builder: (c) => IconButton(
              onPressed: () => Scaffold.of(c).openDrawer(),
              icon: const Icon(Icons.menu),
            ),
          ),
        if (wide)
          Text(
            'Your learning journey',
            style: TextStyle(fontSize: 13, color: muted.withValues(alpha: .9)),
          ),
        const Spacer(),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: role,
            style: const TextStyle(fontSize: 12, color: green),
            items: ['Admin', 'Teacher', 'Student', 'Parent']
                .map(
                  (r) => DropdownMenuItem(value: r, child: Text('$r portal')),
                )
                .toList(),
            onChanged: (r) {
              if (r != null) enter(r);
            },
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Notifications',
          onPressed: notifications,
          icon: const Badge(
            smallSize: 6,
            child: Icon(
              Icons.notifications_none_outlined,
              size: 21,
              color: muted,
            ),
          ),
        ),
        if (wide) const VerticalDivider(indent: 25, endIndent: 25, width: 30),
        InkWell(
          onTap: () => go('Settings'),
          child: Row(
            children: [
              avatar(name, size: 37),
              if (wide) ...[
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '$role account',
                      style: const TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
  Widget demoBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF1EDDF),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Row(
      children: [
        Icon(Icons.science_outlined, size: 17, color: Color(0xFF8A713F)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'DEMO ACADEMY  ·  Fictional records. Changes last for this visit. Real accounts and live classrooms require a connected backend.',
            style: TextStyle(color: Color(0xFF7B6947), fontSize: 10),
          ),
        ),
      ],
    ),
  );
  void notifications() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Your notifications'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your next class is Quran recitation.'),
          SizedBox(height: 16),
          Text('New homework: Revise Surah Al-Fatiha.'),
          SizedBox(height: 16),
          Text(
            'These are sample notifications.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  Widget pageContent(bool wide) => switch (page) {
    'Overview' => overview(wide),
    'Students' => directory(false),
    'Teachers' => directory(true),
    'My children' => childrenPage(),
    'My classes' => classesPage(),
    'Quran progress' => progressPage(),
    'Attendance' => attendancePage(),
    'Resources' => resourcesPage(),
    'Homework' => homeworkPage(),
    'Messages' => messagesPage(wide),
    'Feedback' => feedbackPage(),
    'Reports' => reportsPage(),
    _ => settingsPage(),
  };
  Widget title(String heading, String sub, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 20,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              heading,
              style: const TextStyle(
                fontFamily: 'CormorantGaramond',
                fontSize: 30,
                letterSpacing: -.5,
                color: dark,
              ),
            ),
            const SizedBox(height: 6),
            Text(sub, style: const TextStyle(color: muted, fontSize: 12)),
          ],
        ),
        ?action,
      ],
    ),
  );
  Widget overview(bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: title(
                'Assalamu Alaikum, $firstName',
                'A new day to learn, reflect, and grow.',
              ),
            ),
            if (wide) pill(dateLabel(), muted),
          ],
        ),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(wide ? 30 : 22),
          decoration: BoxDecoration(
            color: green,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BISMILLAH · YOUR JOURNEY CONTINUES',
                      style: TextStyle(
                        color: Color(0xFFBCD6BC),
                        letterSpacing: 1.6,
                        fontSize: 9,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      role == 'Admin'
                          ? 'Nurturing knowledge.\nGrowing together.'
                          : role == 'Teacher'
                          ? 'Inspire a heart.\nTeach an ayah.'
                          : 'Every ayah is a\nstep closer.',
                      style: TextStyle(
                        fontFamily: 'CormorantGaramond',
                        fontSize: wide ? 34 : 28,
                        color: Colors.white,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      role == 'Admin'
                          ? 'Your academy, thoughtfully connected.'
                          : '“The best among you are those who learn\nthe Quran and teach it.” — Sahih al-Bukhari',
                      style: const TextStyle(
                        color: Color(0xFFC7DDD0),
                        fontSize: 11,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () =>
                          go(role == 'Admin' ? 'Students' : 'My classes'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF5EBCF),
                        foregroundColor: dark,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                      ),
                      child: Text(
                        role == 'Admin'
                            ? 'Manage academy  →'
                            : 'View my classes  →',
                      ),
                    ),
                  ],
                ),
              ),
              if (wide)
                const SizedBox(
                  width: 260,
                  height: 190,
                  child: FaithArtwork(transparent: true),
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, c) {
            final count = c.maxWidth > 800 ? 4 : 2;
            final w = (c.maxWidth - (count - 1) * 14) / count;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                metric(
                  w,
                  role == 'Admin'
                      ? 'Students'
                      : role == 'Teacher'
                      ? 'My students'
                      : role == 'Parent'
                      ? 'My children'
                      : 'Learning streak',
                  role == 'Admin'
                      ? '${students.length}'
                      : role == 'Teacher'
                      ? '4'
                      : role == 'Parent'
                      ? '2'
                      : '7 days',
                  Icons.school_outlined,
                  'A little progress, every day',
                  green,
                ),
                metric(
                  w,
                  role == 'Admin' ? 'Teachers' : 'Upcoming classes',
                  role == 'Admin' ? '${teachers.length}' : '${lessons.length}',
                  Icons.calendar_month_outlined,
                  role == 'Admin'
                      ? 'Guiding every learner'
                      : 'Your next step awaits',
                  gold,
                ),
                metric(
                  w,
                  'Attendance',
                  '75%',
                  Icons.fact_check_outlined,
                  '3 of 4 sample lessons',
                  green,
                ),
                metric(
                  w,
                  role == 'Admin' ? 'Active classes' : 'Quran progress',
                  role == 'Admin' ? '${lessons.length}' : 'Juz 1',
                  Icons.menu_book_outlined,
                  role == 'Admin'
                      ? 'Individual & group'
                      : 'Al-Baqarah · 65% complete',
                  const Color(0xFF8170A0),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 26),
        responsiveColumns(
          wide,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sectionLabel(
                role == 'Admin' ? "Academy’s classes" : "Today’s classes",
                'View schedule',
                () => go('My classes'),
              ),
              const SizedBox(height: 14),
              panel(
                Column(
                  children: [for (final lesson in lessons) lessonRow(lesson)],
                ),
              ),
              const SizedBox(height: 24),
              sectionLabel(
                'Continue your journey',
                'View progress',
                () => go('Quran progress'),
              ),
              const SizedBox(height: 14),
              progressCard(),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sectionLabel('Quick access', '', null),
              const SizedBox(height: 14),
              panel(
                LayoutBuilder(
                  builder: (context, c) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      quick(
                        'Attendance',
                        Icons.fact_check_outlined,
                        c.maxWidth,
                      ),
                      quick(
                        'Resources',
                        Icons.library_books_outlined,
                        c.maxWidth,
                      ),
                      quick('Homework', Icons.assignment_outlined, c.maxWidth),
                      quick('Messages', Icons.chat_bubble_outline, c.maxWidth),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              sectionLabel(
                role == 'Parent' ? 'My children' : 'Learning reminders',
                '',
                null,
              ),
              const SizedBox(height: 14),
              panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (role == 'Parent')
                      ...students.take(2).map((s) => personRow(s))
                    else ...[
                      pill('PRACTICE MAKES PROGRESS', gold),
                      const SizedBox(height: 16),
                      const Text(
                        'A moment for revision',
                        style: TextStyle(
                          fontFamily: 'CormorantGaramond',
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Revisit Surah Al-Fatiha and focus on clear pronunciation. Small, consistent steps make a lasting difference.',
                        style: TextStyle(
                          fontSize: 12,
                          color: muted,
                          height: 1.8,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => go('Homework'),
                        child: const Text('See your homework  →'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget metric(
    double width,
    String label,
    String value,
    IconData icon,
    String note,
    Color color,
  ) => SizedBox(
    width: width,
    child: panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              const Icon(Icons.north_east, size: 14, color: muted),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            value,
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w600,
              color: dark,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 12, color: dark)),
          const SizedBox(height: 12),
          Text(note, style: const TextStyle(fontSize: 9, color: muted)),
        ],
      ),
    ),
  );
  Widget quick(String label, IconData icon, double width) => SizedBox(
    width: (width - 12) / 2,
    child: InkWell(
      onTap: () => go(label),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cream,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: green, size: 23),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    ),
  );
  Widget progressCard() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: pale,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_stories_outlined, color: green),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Juz 1 · Al-Baqarah',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Learning one ayah at a time',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
            Text(
              '${(progress['Al-Baqarah']! * 100).round()}%',
              style: const TextStyle(color: green, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 22),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress['Al-Baqarah'],
            minHeight: 7,
            backgroundColor: pale,
            color: green,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Keep going. Every effort is part of your journey.',
          style: TextStyle(color: muted, fontSize: 10),
        ),
      ],
    ),
  );
  Widget lessonRow(Lesson l) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      children: [
        Container(
          width: 65,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: cream,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            l.time,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l.teacher,
                style: const TextStyle(fontSize: 10, color: muted),
              ),
              Text(
                l.category,
                style: const TextStyle(fontSize: 9, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        OutlinedButton(
          onPressed: () => classroom(l),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          ),
          child: const Text('View', style: TextStyle(fontSize: 10)),
        ),
      ],
    ),
  );
  Widget classesPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'My classes',
        'Make space for your next moment of learning.',
        action: role == 'Admin' || role == 'Teacher'
            ? FilledButton.icon(
                onPressed: addClass,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Schedule class'),
              )
            : null,
      ),
      pill('SAMPLE SCHEDULE · ${dateLabel()}', green),
      const SizedBox(height: 18),
      panel(Column(children: lessons.map(lessonRow).toList())),
      const SizedBox(height: 20),
      const Text(
        'Classrooms are previews until the academy server and video provider are connected.',
        style: TextStyle(fontSize: 11, color: muted),
      ),
    ],
  );
  void classroom(Lesson l) => showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.mosque_outlined, color: green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.name,
                      style: const TextStyle(
                        fontFamily: 'CormorantGaramond',
                        fontSize: 24,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(c),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                height: 230,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: dark,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    avatar(l.teacher, size: 70),
                    const SizedBox(height: 14),
                    Text(
                      l.teacher,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'CLASSROOM PREVIEW',
                      style: TextStyle(
                        color: Color(0xFFB6D0B7),
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '${l.time}  ·  ${l.category}',
                style: const TextStyle(
                  color: green,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Live video is not connected in this demo. Real sessions require an academy account and a private room authorized by the backend.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 12, height: 1.7),
              ),
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Back to classes'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Future<void> addClass() async {
    String n = '', t = '09:00 AM', teacher = teachers.first.name;
    final form = GlobalKey<FormState>();
    final added = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Schedule a demo class'),
        content: SizedBox(
          width: 380,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  onChanged: (v) => n = v,
                  maxLength: 100,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter a class name.'
                      : null,
                  decoration: const InputDecoration(labelText: 'Class name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: t,
                  onChanged: (v) => t = v,
                  validator: (v) =>
                      v == null ||
                          !RegExp(
                            r'^(0?[1-9]|1[0-2]):[0-5][0-9] (AM|PM)$',
                          ).hasMatch(v.trim())
                      ? 'Use a time such as 09:00 AM.'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Time (e.g. 09:00 AM)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: teacher,
                  items: teachers
                      .map(
                        (p) => DropdownMenuItem(
                          value: p.name,
                          child: Text(p.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => teacher = v!,
                  decoration: const InputDecoration(labelText: 'Teacher'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, true);
            },
            child: const Text('Schedule'),
          ),
        ],
      ),
    );
    if (added == true && mounted) {
      setState(
        () =>
            lessons.add(Lesson(n.trim(), teacher, t.trim(), 'Group · 30 min')),
      );
      toast('Class added to this demo session.');
    }
  }

  Widget directory(bool isTeacher) {
    final list = isTeacher ? teachers : students;
    final filtered = list
        .where(
          (p) => '${p.name} ${p.email} ${p.level}'.toLowerCase().contains(
            search.toLowerCase(),
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title(
          isTeacher ? 'Our teachers' : 'Our students',
          'A community of learning, connected by the Quran.',
          action: FilledButton.icon(
            onPressed: () => addPerson(isTeacher),
            icon: const Icon(Icons.add, size: 18),
            label: Text(isTeacher ? 'Add teacher' : 'Add student'),
          ),
        ),
        searchField(isTeacher ? 'Search teachers…' : 'Search students…'),
        const SizedBox(height: 20),
        panel(
          Column(
            children: [
              if (filtered.isEmpty)
                empty(
                  'No matching records',
                  'Try another name or add a new record.',
                ),
              for (final p in filtered)
                personRow(
                  p,
                  action: IconButton(
                    tooltip: 'View details',
                    onPressed: () => personDetails(p),
                    icon: const Icon(
                      Icons.arrow_forward,
                      size: 18,
                      color: green,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget personRow(Person p, {Widget? action}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        avatar(p.name),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(p.level, style: const TextStyle(fontSize: 10, color: muted)),
            ],
          ),
        ),
        action ?? pill('Active', green),
      ],
    ),
  );
  void personDetails(Person p) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(p.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.email),
          const SizedBox(height: 8),
          Text(p.level),
          const SizedBox(height: 20),
          const Text(
            'Fictional academy profile',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  Future<void> addPerson(bool teacher) async {
    String n = '', e = '', l = teacher ? 'Tajweed' : 'Level 1';
    final form = GlobalKey<FormState>();
    final list = teacher ? teachers : students;
    final added = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(teacher ? 'Add demo teacher' : 'Add demo student'),
        content: SizedBox(
          width: 380,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  onChanged: (v) => n = v,
                  maxLength: 80,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a name.' : null,
                  decoration: const InputDecoration(labelText: 'Full name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  onChanged: (v) => e = v,
                  maxLength: 160,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null ||
                        !RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(v.trim())) {
                      return 'Enter a valid email address.';
                    }
                    if (list.any(
                      (p) => p.email.toLowerCase() == v.trim().toLowerCase(),
                    )) {
                      return 'This email is already in the demo directory.';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: l,
                  onChanged: (v) => l = v,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: teacher ? 'Specialty' : 'Learning level',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, true);
            },
            child: const Text('Add record'),
          ),
        ],
      ),
    );
    if (added == true && mounted) {
      setState(() => list.add(Person(n.trim(), e.trim(), l.trim())));
      toast('Demo record added. No account or invitation was created.');
    }
  }

  Widget childrenPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title('My children', 'Be part of every step in their learning journey.'),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var i = 0; i < 2; i++)
            ChoiceChip(
              label: Text(students[i].name),
              selected: selectedChild == i,
              onSelected: (_) => setState(() => selectedChild = i),
            ),
        ],
      ),
      const SizedBox(height: 20),
      panel(personRow(students[selectedChild])),
      const SizedBox(height: 20),
      selectedChild == 0
          ? progressCard()
          : panel(
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Juz 2 · Al-Baqarah',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: .4,
                    color: green,
                    backgroundColor: pale,
                  ),
                  SizedBox(height: 10),
                  Text(
                    '40% complete · Level 2',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
      const SizedBox(height: 20),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Teacher’s note',
              style: TextStyle(fontFamily: 'CormorantGaramond', fontSize: 22),
            ),
            const SizedBox(height: 12),
            Text(
              selectedChild == 0
                  ? 'Ali is making steady progress with his pronunciation. Please help him revise Al-Fatiha each evening.'
                  : 'Fatima is growing in confidence with her memorization. A short daily revision will help her retain what she has learned.',
              style: const TextStyle(color: muted, height: 1.8),
            ),
          ],
        ),
      ),
    ],
  );
  Widget progressPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'Quran progress',
        'Every verse learned is a milestone worth celebrating.',
      ),
      progressCard(),
      const SizedBox(height: 24),
      panel(
        Column(
          children: [
            for (final entry in progress.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 17),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: entry.value == 1 ? pale : cream,
                      child: Text(
                        '${progress.keys.toList().indexOf(entry.key) + 1}',
                        style: const TextStyle(fontSize: 12, color: green),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            entry.value == 1
                                ? 'Completed'
                                : entry.value == 0
                                ? 'Not started'
                                : 'In progress · ${(entry.value * 100).round()}%',
                            style: const TextStyle(fontSize: 10, color: muted),
                          ),
                          if (entry.value > 0 && entry.value < 1) ...[
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: entry.value,
                              color: green,
                              backgroundColor: pale,
                              minHeight: 5,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    if (role == 'Teacher' || role == 'Admin')
                      IconButton(
                        tooltip: 'Update progress',
                        onPressed: () => editProgress(entry.key),
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: green,
                        ),
                      )
                    else
                      Icon(
                        entry.value == 1
                            ? Icons.check_circle_outline
                            : Icons.menu_book_outlined,
                        color: entry.value == 1 ? green : muted,
                        size: 20,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
  void editProgress(String surah) {
    double value = progress[surah]!;
    showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text('Update $surah'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${(value * 100).round()}% complete'),
              Slider(
                value: value,
                divisions: 20,
                onChanged: (v) => update(() => value = v),
              ),
              const Text(
                'Saved for this demo visit only.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                setState(() => progress[surah] = value);
                Navigator.pop(c);
              },
              child: const Text('Save progress'),
            ),
          ],
        ),
      ),
    );
  }

  Widget attendancePage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title('Attendance', 'Consistency is the heart of a meaningful journey.'),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(Icons.calendar_month_outlined, color: green),
                Text(
                  dateLabel(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                pill(
                  '${attendance.values.where((v) => v).length} / ${attendance.length} present',
                  green,
                ),
              ],
            ),
            const SizedBox(height: 24),
            for (final entry in attendance.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Sample class record',
                            style: TextStyle(color: muted, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    if (role == 'Teacher' || role == 'Admin')
                      Switch(
                        value: entry.value,
                        onChanged: (v) =>
                            setState(() => attendance[entry.key] = v),
                      )
                    else
                      pill(
                        entry.value ? 'Present' : 'Absent',
                        entry.value ? green : const Color(0xFFBD6656),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      if (role == 'Teacher' || role == 'Admin')
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text(
            'Toggle a class to mark attendance in the demo.',
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ),
    ],
  );
  final resources = const [
    (
      'A gentle introduction to Tajweed',
      'Reading',
      'The art of reciting with care',
      'Tajweed means giving each letter its due right. Begin with the points of articulation (makharij), listen attentively to your teacher, and practice slowly.\n\nPractice: recite Al-Fatiha at a measured pace. Pause at the end of each ayah and ask your teacher for feedback on clarity.\n\nThis is an introductory study note, not a substitute for guided instruction.',
    ),
    (
      'Your daily memorization routine',
      'Reading',
      'Small steps. Lasting knowledge.',
      '1. Choose a quiet time and a small passage.\n2. Listen to a qualified reciter.\n3. Read while looking at the mushaf.\n4. Repeat in short sections.\n5. Recite from memory to your teacher.\n6. Revise previous passages daily.\n\nConsistency matters more than speed. Ask your teacher to set an appropriate pace.',
    ),
    (
      'Arabic letters · practice guide',
      'Practice',
      'Build a strong foundation',
      'Practice recognizing these letters with your teacher:\n\nا  ب  ت  ث  ج  ح  خ\nد  ذ  ر  ز  س  ش\nص  ض  ط  ظ  ع  غ\nف  ق  ك  ل  م  ن  ه  و  ي\n\nListen carefully to each sound. Pay attention to letters that share a shape but differ in their dots.',
    ),
    (
      'Before your next class',
      'Practice',
      'A little preparation goes a long way',
      'Find a quiet place. Have your Quran and notes ready. Review your last lesson. Write down questions for your teacher.\n\nDuring your lesson, listen carefully, take your time, and ask when you are unsure. Finish by noting what to practice before your next class.',
    ),
  ];
  Widget resourcesPage() {
    final list = resources
        .where(
          (r) =>
              (resourceFilter == 'All' || r.$2 == resourceFilter) &&
              r.$1.toLowerCase().contains(search.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title(
          'Learning resources',
          'A little guidance for the moments between classes.',
        ),
        searchField('Search learning resources…'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: ['All', 'Reading', 'Practice']
              .map(
                (f) => ChoiceChip(
                  label: Text(f),
                  selected: resourceFilter == f,
                  onSelected: (_) => setState(() => resourceFilter = f),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        if (list.isEmpty)
          empty('No resources found', 'Try a different search or category.'),
        for (final r in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => readResource(r),
              borderRadius: BorderRadius.circular(14),
              child: panel(
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: pale,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        r.$2 == 'Reading'
                            ? Icons.description_outlined
                            : Icons.auto_stories_outlined,
                        color: green,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.$1,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${r.$2} · ${r.$3}',
                            style: const TextStyle(fontSize: 10, color: muted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward, size: 18, color: green),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void readResource((String, String, String, String) r) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(
        r.$1,
        style: const TextStyle(fontFamily: 'CormorantGaramond'),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: SelectableText(
            r.$4,
            style: const TextStyle(height: 1.9, fontSize: 15),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: '${r.$1}\n\n${r.$4}'));
            toast('Study note copied.');
          },
          child: const Text('Copy study note'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Done'),
        ),
      ],
    ),
  );
  Widget homeworkPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title('Homework', 'Let today’s practice become tomorrow’s progress.'),
      for (final task in [
        'Revise Surah Al-Fatiha',
        'Practice Arabic letter sounds',
        'Review Al-Baqarah · verses 1–5',
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: panel(
            Row(
              children: [
                Checkbox(
                  value: homeworkDone.contains(task),
                  onChanged: role == 'Student'
                      ? (v) => setState(() {
                          if (v == true) {
                            homeworkDone.add(task);
                          } else {
                            homeworkDone.remove(task);
                          }
                        })
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          decoration: homeworkDone.contains(task)
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        homeworkDone.contains(task)
                            ? 'Completed in this demo'
                            : 'For your next lesson · assigned by Ustadh Ahmed',
                        style: const TextStyle(color: muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                Icon(
                  homeworkDone.contains(task)
                      ? Icons.check_circle_outline
                      : Icons.assignment_outlined,
                  color: homeworkDone.contains(task) ? green : gold,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      const Text(
        'Students can mark tasks complete. These changes are not submitted to a teacher.',
        style: TextStyle(color: muted, fontSize: 11),
      ),
    ],
  );
  Widget messagesPage(bool wide) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title('Messages', 'Stay connected with your learning community.'),
      const Text(
        'Demo conversation · messages are local to this visit and are not delivered.',
        style: TextStyle(color: muted, fontSize: 11),
      ),
      const SizedBox(height: 18),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['Ustadh Ahmed', 'Academy Admin', 'Class group']
                  .map(
                    (n) => ChoiceChip(
                      label: Text(n),
                      selected: conversation == n,
                      onSelected: (_) => setState(() => conversation = n),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                avatar(conversation),
                const SizedBox(width: 12),
                Text(
                  conversation,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                pill('Demo', gold),
              ],
            ),
            const Divider(height: 32),
            SizedBox(
              height: 300,
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var i = 0;
                      i <
                          (conversation == 'Ustadh Ahmed'
                              ? messages.length
                              : 1);
                      i++
                    )
                      Align(
                        alignment: i == 0
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 440),
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: i == 0 ? cream : pale,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            conversation == 'Ustadh Ahmed'
                                ? messages[i]
                                : 'Welcome to your demo conversation. No messages have been sent.',
                            style: const TextStyle(fontSize: 13, height: 1.7),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: composer,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 3,
                    onSubmitted: (_) => sendMessage(),
                    decoration: const InputDecoration(
                      hintText: 'Write a demo message…',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  tooltip: 'Add demo message',
                  onPressed: sendMessage,
                  icon: const Icon(Icons.send_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
  void sendMessage() {
    final text = composer.text.trim();
    if (text.isEmpty) return;
    if (conversation != 'Ustadh Ahmed') {
      toast('Select Ustadh Ahmed to try the sample conversation.');
      return;
    }
    setState(() => messages.add(text));
    composer.clear();
  }

  Widget feedbackPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title(
        'Share your feedback',
        'Your voice helps us nurture a better academy.',
      ),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How is your child’s learning experience?',
              style: TextStyle(fontFamily: 'CormorantGaramond', fontSize: 23),
            ),
            const SizedBox(height: 18),
            Wrap(
              children: List.generate(
                5,
                (i) => IconButton(
                  tooltip: '${i + 1} stars',
                  onPressed: () => setState(() => rating = i + 1),
                  icon: Icon(
                    i < rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: gold,
                    size: 32,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: feedback,
              maxLines: 5,
              maxLength: 1500,
              decoration: const InputDecoration(
                hintText: 'What is going well? What could we improve?',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                if (feedback.text.trim().isEmpty) {
                  toast('Please write your feedback first.');
                  return;
                }
                feedback.clear();
                toast(
                  'Demo feedback recorded for this visit. It has not been sent to the academy.',
                );
              },
              child: const Text('Try feedback submission'),
            ),
          ],
        ),
      ),
    ],
  );
  Widget reportsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title('Academy reports', 'A thoughtful view of your learning community.'),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Demo academy summary',
              style: TextStyle(fontFamily: 'CormorantGaramond', fontSize: 24),
            ),
            const SizedBox(height: 24),
            reportLine('Students', '${students.length}'),
            reportLine('Teachers', '${teachers.length}'),
            reportLine('Scheduled classes', '${lessons.length}'),
            reportLine(
              'Sample attendance',
              '${(attendance.values.where((v) => v).length / attendance.length * 100).round()}%',
            ),
            reportLine(
              'Completed sample Surahs',
              '${progress.values.where((v) => v == 1).length}',
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(
                    text:
                        'Al Hassan Online Quran Academy — DEMO REPORT\nStudents: ${students.length}\nTeachers: ${teachers.length}\nClasses: ${lessons.length}\nFictional sample records only.',
                  ),
                );
                toast('Demo report copied.');
              },
              icon: const Icon(Icons.copy_outlined, size: 17),
              label: const Text('Copy demo summary'),
            ),
          ],
        ),
      ),
    ],
  );
  Widget reportLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: muted)),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, color: green),
        ),
      ],
    ),
  );
  Widget settingsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      title('My profile & settings', 'Your own space in the academy.'),
      panel(
        Column(
          children: [
            avatar(name, size: 80),
            const SizedBox(height: 18),
            Text(
              name,
              style: const TextStyle(
                fontFamily: 'CormorantGaramond',
                fontSize: 28,
              ),
            ),
            const SizedBox(height: 6),
            pill('$role · demo profile', green),
            const SizedBox(height: 28),
            settingsRow(
              Icons.person_outline,
              'Personal information',
              'Fictional profile',
              () => personDetails(
                Person(name, '${role.toLowerCase()}@example.test', role),
              ),
            ),
            settingsRow(
              Icons.lock_outline,
              'Account security',
              'Backend required',
              () => info(
                'Account security',
                'This demo does not create accounts or store passwords. Secure server-side sessions and account administration must be connected before real enrollment.',
              ),
            ),
            settingsRow(
              Icons.language_outlined,
              'Language',
              'English',
              () => info(
                'Language',
                'The interface is currently available in English. Arabic study content is included in learning resources.',
              ),
            ),
            settingsRow(
              Icons.help_outline,
              'Help & support',
              'Academy information',
              showAbout,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => setState(() => entered = false),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Leave demo'),
            ),
          ],
        ),
      ),
    ],
  );
  Widget settingsRow(
    IconData icon,
    String label,
    String trailing,
    VoidCallback onTap,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, size: 20, color: green),
    title: Text(label, style: const TextStyle(fontSize: 13)),
    subtitle: Text(
      trailing,
      style: const TextStyle(fontSize: 10, color: muted),
    ),
    trailing: const Icon(Icons.chevron_right, size: 18),
    onTap: onTap,
  );
  void info(String title, String text) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(text, style: const TextStyle(height: 1.8)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  Widget searchField(String hint) => TextField(
    controller: searchController,
    onChanged: (s) => setState(() => search = s),
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search, size: 20),
      fillColor: Colors.white,
    ),
  );
  Widget empty(String heading, String sub) => Padding(
    padding: const EdgeInsets.all(30),
    child: Column(
      children: [
        const Icon(Icons.search_off, color: muted, size: 36),
        const SizedBox(height: 12),
        Text(heading),
        const SizedBox(height: 8),
        Text(sub, style: const TextStyle(color: muted, fontSize: 12)),
      ],
    ),
  );
  Widget footer() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 12),
    child: Text(
      'AL HASSAN ONLINE QURAN ACADEMY  ·  Learn. Practice. Grow.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 9, color: muted, letterSpacing: 1),
    ),
  );
}

Widget panel(Widget child) => SizedBox(
  width: double.infinity,
  child: Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Color(0xFFE7EBE3)),
    ),
    child: Padding(padding: const EdgeInsets.all(22), child: child),
  ),
);
Widget pill(String text, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
  decoration: BoxDecoration(
    color: color.withValues(alpha: .08),
    borderRadius: BorderRadius.circular(6),
  ),
  child: Text(
    text,
    style: TextStyle(
      color: color,
      fontSize: 9,
      fontWeight: FontWeight.w600,
      letterSpacing: .4,
    ),
  ),
);
Widget avatar(String name, {double size = 42}) => Container(
  width: size,
  height: size,
  decoration: BoxDecoration(
    color: pale,
    borderRadius: BorderRadius.circular(size / 2),
    border: Border.all(color: Colors.white, width: 3),
  ),
  alignment: Alignment.center,
  child: Text(
    name.split(' ').where((s) => s.isNotEmpty).take(2).map((s) => s[0]).join(),
    style: TextStyle(
      color: green,
      fontSize: size * .29,
      fontWeight: FontWeight.w600,
    ),
  ),
);
Widget sectionLabel(String title, String action, VoidCallback? onTap) => Row(
  children: [
    Expanded(
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'CormorantGaramond',
          fontSize: 21,
          color: dark,
        ),
      ),
    ),
    if (onTap != null)
      TextButton(
        onPressed: onTap,
        child: Text('$action  →', style: const TextStyle(fontSize: 10)),
      ),
  ],
);
Widget feature(IconData icon, String title, String sub) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(icon, color: green, size: 26),
    const SizedBox(width: 16),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 5),
        Text(sub, style: const TextStyle(color: muted, fontSize: 10)),
      ],
    ),
  ],
);
Widget responsiveColumns(bool wide, Widget left, Widget right) => wide
    ? Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 7, child: left),
          const SizedBox(width: 24),
          Expanded(flex: 4, child: right),
        ],
      )
    : Column(children: [left, const SizedBox(height: 24), right]);
String dateLabel() {
  final d = DateTime.now();
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

IconData roleIcon(String role) => switch (role) {
  'Admin' => Icons.admin_panel_settings_outlined,
  'Teacher' => Icons.school_outlined,
  'Parent' => Icons.family_restroom_outlined,
  _ => Icons.auto_stories_outlined,
};
String roleDescription(String role) => switch (role) {
  'Admin' => 'Nurture and manage the academy',
  'Teacher' => 'Guide learners. Inspire progress.',
  'Parent' => 'Be part of your child’s journey',
  _ => 'Learn Quran, one step at a time',
};
IconData navIcon(String p) => switch (p) {
  'Overview' => Icons.grid_view_rounded,
  'Students' => Icons.people_outline,
  'Teachers' => Icons.school_outlined,
  'My children' => Icons.family_restroom_outlined,
  'My classes' => Icons.calendar_month_outlined,
  'Quran progress' => Icons.insights_outlined,
  'Attendance' => Icons.fact_check_outlined,
  'Resources' => Icons.library_books_outlined,
  'Homework' => Icons.assignment_outlined,
  'Messages' => Icons.chat_bubble_outline,
  'Feedback' => Icons.star_outline,
  'Reports' => Icons.bar_chart_outlined,
  _ => Icons.settings_outlined,
};

class FlexibleOrBox extends StatelessWidget {
  final bool flex;
  final Widget child;
  const FlexibleOrBox({super.key, required this.flex, required this.child});
  @override
  Widget build(BuildContext context) => flex ? Expanded(child: child) : child;
}

class FaithArtwork extends StatelessWidget {
  final bool transparent;
  const FaithArtwork({super.key, this.transparent = false});
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: ArchPainter(transparent),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.nightlight_round,
            color: transparent ? const Color(0xFFDFC891) : gold,
            size: transparent ? 30 : 46,
          ),
          const SizedBox(height: 12),
          Icon(
            Icons.mosque_outlined,
            size: transparent ? 95 : 140,
            color: transparent ? const Color(0xFFBCD2B5) : green,
          ),
          if (!transparent) ...[
            const SizedBox(height: 12),
            const Text(
              'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
              style: TextStyle(fontSize: 25, color: green),
            ),
            const SizedBox(height: 14),
            const Text(
              'LEARN · PRACTICE · GROW',
              style: TextStyle(fontSize: 9, letterSpacing: 3, color: gold),
            ),
          ],
        ],
      ),
    ),
  );
}

class ArchPainter extends CustomPainter {
  final bool transparent;
  ArchPainter(this.transparent);
  @override
  void paint(Canvas canvas, Size s) {
    final bg = Paint()
      ..color = transparent ? const Color(0xFF246B51) : const Color(0xFFE8EDDF);
    final x = s.width * .08,
        y = s.height * .04,
        w = s.width * .84,
        h = s.height * .92;
    final path = Path()
      ..moveTo(x, y + h)
      ..lineTo(x, y + h * .43)
      ..cubicTo(x, y + h * .18, x + w * .35, y + h * .17, x + w * .5, y)
      ..cubicTo(
        x + w * .65,
        y + h * .17,
        x + w,
        y + h * .18,
        x + w,
        y + h * .43,
      )
      ..lineTo(x + w, y + h)
      ..close();
    canvas.drawPath(path, bg);
    canvas.drawPath(
      path,
      Paint()
        ..color = gold.withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.save();
    canvas.clipPath(path);
    final line = Paint()
      ..color = gold.withValues(alpha: .12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (double a = 0; a < s.width; a += 40) {
      for (double b = 0; b < s.height; b += 40) {
        canvas.drawPath(
          Path()
            ..moveTo(a + 20, b)
            ..lineTo(a + 40, b + 20)
            ..lineTo(a + 20, b + 40)
            ..lineTo(a, b + 20)
            ..close(),
          line,
        );
      }
    }
    canvas.restore();
    if (!transparent) {
      final p = Paint()..color = green.withValues(alpha: .6);
      for (var i = 0; i < 5; i++) {
        final offset = i * 14.0;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(x + offset, y + h - 20 - offset * 1.2),
            width: 18,
            height: 40,
          ),
          p,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(x + w - offset, y + h - 20 - offset * 1.2),
            width: 18,
            height: 40,
          ),
          p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ArchPainter old) =>
      transparent != old.transparent;
}
