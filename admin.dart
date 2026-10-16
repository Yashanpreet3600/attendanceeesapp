import 'package:flutter/material.dart';
import 'main.dart'; // For logout navigation (LoginScreen)
import 'app_session.dart';
import 'message_service.dart';
import 'academic_service.dart';
import 'admin_service.dart';
import 'performance_page.dart';
import 'communication_page.dart';
import 'notification_service.dart';
import 'password_dialog.dart';

// ==========================================
// 1. DATA MODELS
// ==========================================

// Mock Data for Classes
List<Map<String, dynamic>> allClasses = [
  {
    'className': 'CS - Year 1 (Sec A)',
    'dept': 'Computer Science',
    'studentCount': 54,
    'room': 'B-101',
    'teacher': 'Prof. Anjali',
    'attendanceAvg': 0.85,
    'testScores': [
      {'date': '20 Nov', 'topic': 'Java Basics', 'avg': 78, 'total': 100},
      {'date': '13 Nov', 'topic': 'OOPs Concept', 'avg': 65, 'total': 100},
    ]
  },
  {
    'className': 'CS - Year 3 (Sec B)',
    'dept': 'Computer Science',
    'studentCount': 45,
    'room': 'C-202',
    'teacher': 'Dr. Sharma',
    'attendanceAvg': 0.91,
    'testScores': []
  },
  {
    'className': 'ME - Year 1',
    'dept': 'Mechanical Eng',
    'studentCount': 60,
    'room': 'LAB-1',
    'teacher': 'Mr. Rahul',
    'attendanceAvg': 0.65,
    'testScores': [
      {'date': '18 Nov', 'topic': 'Thermodynamics', 'avg': 55, 'total': 100},
    ]
  },
];

// Mock Data for Faculty
List<Map<String, dynamic>> allFaculty = [
  {
    'name': 'Dr. Sharma',
    'dept': 'Computer Science',
    'role': 'HOD',
    'subjects': [
      {'name': 'Data Structures', 'class': 'CS - Year 3 (Sec B)', 'dept': 'Computer Science'},
      {'name': 'AI Basics', 'class': 'CS - Year 3 (Sec B)', 'dept': 'Computer Science'}
    ]
  },
  {
    'name': 'Prof. Anjali',
    'dept': 'Computer Science',
    'role': 'Assistant Prof',
    'subjects': [
      {'name': 'Java', 'class': 'CS - Year 1 (Sec A)', 'dept': 'Computer Science'},
      {'name': 'Web Dev', 'class': 'CS - Year 3 (Sec B)', 'dept': 'Computer Science'}
    ]
  },
  {
    'name': 'Mr. Rahul',
    'dept': 'Mechanical Eng',
    'role': 'Lab Assistant',
    'subjects': [
      {'name': 'Thermodynamics', 'class': 'ME - Year 1', 'dept': 'Mechanical Eng'}
    ]
  },
];

// Mock Data for Students
Map<String, List<String>> mockStudents = {
  'CS - Year 1 (Sec A)': ['Amit Kumar', 'Priya Singh', 'Rohan Das'],
  'CS - Year 3 (Sec B)': ['Vikram R', 'Sneha G', 'Arun K'],
  'ME - Year 1': ['John Doe', 'Mike Ross'],
};

// Timetable Data
Map<String, List<Map<String, String>>> timetableData = {
  'CS - Year 1 (Sec A)': [
    {'time': '09:00 AM', 'title': 'Java', 'sub': 'Prof. Anjali (Room B-101)'},
    {'time': '10:00 AM', 'title': 'Maths', 'sub': 'Dr. X (Room B-102)'},
  ],
  'Prof. Anjali': [
    {'time': '09:00 AM', 'title': 'Java', 'sub': 'CS - Year 1 (Sec A)'},
  ]
};

// ==========================================
// 3. MAIN DASHBOARD
// ==========================================
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with SingleTickerProviderStateMixin {
  int _sideBarIndex = 0;
  late TabController _tabController;

  // Logged-in admin (from Supabase)
  final AppUser? me = AppSession.currentUser;

  // Departments for the filter (null = all departments)
  Map<int, String> _departments = {};
  int? _selectedDeptId;

  // Faculty tab (from Supabase)
  List<FacultyMember> _faculty = [];
  bool _loadingFaculty = true;
  String? _facultyError;

  // Messages to the admin office (delivered like leave requests)
  InboxController? _inbox;
  int get _inboxCount => _inbox?.unreadCount ?? 0;

  // Logout goes back to the main login screen and clears the history
  void _logout() {
    AppSession.signOut();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen()),
      (Route<dynamic> route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadDepartments();
    _loadFaculty();
    _startInbox();
  }

  @override
  void dispose() {
    _inbox?.removeListener(_onInboxChanged);
    _inbox?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    try {
      final rows = await supabase.from('departments').select('id, name').order('name', ascending: true);
      if (!mounted) return;
      setState(() => _departments = {for (final r in rows) r['id'] as int: r['name'] as String});
    } catch (e) {
      debugPrint('Load departments error: $e');
    }
  }

  Future<void> _loadFaculty() async {
    setState(() {
      _loadingFaculty = true;
      _facultyError = null;
    });
    try {
      final list = await AdminService.loadFaculty(departmentId: _selectedDeptId);
      if (!mounted) return;
      setState(() {
        _faculty = list;
        _loadingFaculty = false;
      });
    } catch (e) {
      debugPrint('Load faculty error: $e');
      if (mounted) {
        setState(() {
          _loadingFaculty = false;
          _facultyError = 'Could not load faculty. Check your internet connection.';
        });
      }
    }
  }

  void _startInbox() {
    final admin = me;
    if (admin == null) return;
    _inbox = InboxController(
      userId: admin.id,
      onNewMessage: (item) {
        NotificationService.show("New message from ${item.fromLabel}", item.title);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("New message from ${item.fromLabel}: ${item.title}"),
          backgroundColor: Colors.indigo,
          action: SnackBarAction(
            label: 'VIEW',
            textColor: Colors.white,
            onPressed: () => setState(() => _sideBarIndex = 3),
          ),
        ));
      },
    )..start();
    _inbox!.addListener(_onInboxChanged);
  }

  void _onInboxChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;
    String title;

    switch (_sideBarIndex) {
      case 1:
        bodyContent = const ClassPerformancePage(showAppBar: false);
        title = "Class Performance";
        break;
      case 2:
        bodyContent = const HierarchicalTimetablePage();
        title = "Timetable Manager";
        break;
      case 3:
        bodyContent = const CommunicationPage(embedded: true);
        title = "Messages";
        break;
      case 0:
      default:
        bodyContent = _buildDashboardTabs();
        title = "Admin Console";
        break;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        title: Text(title),
        elevation: 0,
        actions: [
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.mail_outline),
                if (_inboxCount > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
                      child: Text('$_inboxCount', style: const TextStyle(color: Colors.white, fontSize: 9)),
                    ),
                  ),
              ],
            ),
            tooltip: "Messages",
            onPressed: () => setState(() => _sideBarIndex = 3),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: _logout,
          )
        ],
        bottom: _sideBarIndex == 0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(110),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: _selectedDeptId,
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.indigo),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text("All Departments", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                            ),
                            ..._departments.entries.map((d) => DropdownMenuItem<int?>(
                                  value: d.key,
                                  child: Text(d.value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                                )),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedDeptId = val);
                            _loadFaculty();
                          },
                        ),
                      ),
                    ),
                    TabBar(
                      controller: _tabController,
                      indicatorColor: Colors.white,
                      indicatorWeight: 4,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white60,
                      tabs: const [
                        Tab(text: "FACULTY", icon: Icon(Icons.people)),
                        Tab(text: "CLASSES", icon: Icon(Icons.class_outlined)),
                      ],
                    ),
                  ],
                ),
              )
            : null,
      ),
      drawer: _buildDrawer(),
      body: bodyContent,
    );
  }

  // ===============================================
  // 4. DASHBOARD TABS (HOME)
  // ===============================================
  Widget _buildDashboardTabs() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildFacultyTab(),
        // --- TAB 2: CLASSES (real attendance + Monday Test performance) ---
        ClassPerformancePage(
          key: ValueKey('classes-$_selectedDeptId'),
          departmentId: _selectedDeptId,
          lockDepartment: true,
          showAppBar: false,
        ),
      ],
    );
  }

  // --- TAB 1: FACULTY (from Supabase) ---
  Widget _buildFacultyTab() {
    if (_loadingFaculty) return const Center(child: CircularProgressIndicator());
    if (_facultyError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_facultyError!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            TextButton.icon(onPressed: _loadFaculty, icon: const Icon(Icons.refresh), label: const Text("Try again")),
          ],
        ),
      );
    }
    if (_faculty.isEmpty) {
      return const Center(child: Text("No faculty in this department.", style: TextStyle(color: Colors.grey)));
    }

    return RefreshIndicator(
      onRefresh: _loadFaculty,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _faculty.length,
        itemBuilder: (ctx, i) {
          final f = _faculty[i];
          final isHod = f.designation == 'HOD';
          return Card(
            elevation: 2,
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: isHod ? Colors.orange.shade100 : Colors.indigo.shade50,
                child: Text(f.name.isEmpty ? '?' : f.name[0]),
              ),
              title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("${f.designation ?? 'Faculty'}  |  ${f.loginId}"
                  "${_departments[f.departmentId] != null ? '  |  ${_departments[f.departmentId]}' : ''}"),
              trailing: Text("${f.subjects.length} subject${f.subjects.length == 1 ? '' : 's'}",
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Assigned Subjects:", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (f.subjects.isEmpty)
                        const Text("No subjects assigned yet.", style: TextStyle(fontStyle: FontStyle.italic)),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: f.subjects
                            .map((sub) => Chip(
                                  label: Text("${sub.name}\n(${sub.className})"),
                                  backgroundColor: Colors.indigo.shade50,
                                  labelStyle: TextStyle(color: Colors.indigo[900], fontSize: 12),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _showSubjectManager(f),
                            icon: const Icon(Icons.edit_note, size: 18),
                            label: const Text("Manage Subjects"),
                          ),
                        ],
                      )
                    ],
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  // ===============================================
  // 5. SUBJECT MANAGER (saves to Supabase)
  // ===============================================
  Future<void> _showSubjectManager(FacultyMember faculty) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SubjectManagerDialog(faculty: faculty),
    );
    if (changed == true) _loadFaculty();
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Colors.indigo),
            accountName: Text(me?.fullName ?? "Admin Console"),
            accountEmail: Text("Admin ID: ${me?.loginId ?? '-'}"),
            currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.school, color: Colors.indigo)),
          ),
          _drawerItem(0, Icons.dashboard, "Dashboard"),
          _drawerItem(1, Icons.insights, "Class Performance"),
          _drawerItem(2, Icons.calendar_today, "Timetables"),
          _drawerItem(3, Icons.forum, "Messages", badge: _inboxCount),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text("Change Password"),
            onTap: () {
              Navigator.pop(context);
              showChangePasswordDialog(context);
            },
          ),
          const Divider(),
          ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text("Logout", style: TextStyle(color: Colors.red)), onTap: _logout),
        ],
      ),
    );
  }

  Widget _drawerItem(int index, IconData icon, String label, {int badge = 0}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: _sideBarIndex == index,
      trailing: badge > 0
          ? CircleAvatar(radius: 11, backgroundColor: Colors.red, child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 11)))
          : null,
      onTap: () {
        setState(() => _sideBarIndex = index);
        Navigator.pop(context);
      },
    );
  }
}

// ==========================================
// SUBJECT MANAGER DIALOG
// Remove a subject from a teacher, give them an existing subject,
// or create a new subject for a class.
// ==========================================
class _SubjectManagerDialog extends StatefulWidget {
  final FacultyMember faculty;
  const _SubjectManagerDialog({required this.faculty});

  @override
  State<_SubjectManagerDialog> createState() => _SubjectManagerDialogState();
}

class _SubjectManagerDialogState extends State<_SubjectManagerDialog> {
  static const int _newSubject = -1;

  late List<SubjectInfo> _subjects = [...widget.faculty.subjects];
  List<Map<String, dynamic>> _classes = [];
  int? _classId;
  List<ClassSubjectOption> _classSubjects = [];
  int? _subjectChoice; // a subject id, or _newSubject
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  bool _busy = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    try {
      final classes = await AdminService.loadClasses();
      if (!mounted) return;
      // Classes of the teacher's own department first
      classes.sort((a, b) {
        final aMine = a['department_id'] == widget.faculty.departmentId ? 0 : 1;
        final bMine = b['department_id'] == widget.faculty.departmentId ? 0 : 1;
        if (aMine != bMine) return aMine - bMine;
        return (a['name'] as String).compareTo(b['name'] as String);
      });
      setState(() => _classes = classes);
    } catch (e) {
      debugPrint('Load classes error: $e');
      if (mounted) setState(() => _error = 'Could not load classes. Check your internet connection.');
    }
  }

  Future<void> _loadClassSubjects(int classId) async {
    setState(() {
      _classId = classId;
      _classSubjects = [];
      _subjectChoice = null;
      _error = null;
    });
    try {
      final list = await AdminService.loadClassSubjects(classId);
      if (mounted) setState(() => _classSubjects = list);
    } catch (e) {
      debugPrint('Load class subjects error: $e');
      if (mounted) setState(() => _error = 'Could not load subjects of this class.');
    }
  }

  Future<void> _refreshSubjects() async {
    final list = await AcademicService.loadFacultySubjects(widget.faculty.id);
    if (mounted) setState(() => _subjects = list);
  }

  Future<void> _remove(SubjectInfo sub) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminService.unassignSubject(sub.id);
      _changed = true;
      await _refreshSubjects();
    } catch (e) {
      debugPrint('Unassign subject error: $e');
      if (mounted) setState(() => _error = 'Could not remove the subject. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assign() async {
    final classId = _classId;
    final choice = _subjectChoice;
    if (classId == null || choice == null) {
      setState(() => _error = 'Choose a class and a subject.');
      return;
    }
    if (choice == _newSubject && (_nameCtrl.text.trim().isEmpty || _codeCtrl.text.trim().isEmpty)) {
      setState(() => _error = 'Enter the new subject name and code.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (choice == _newSubject) {
        await AdminService.createSubject(
          classId: classId,
          name: _nameCtrl.text,
          code: _codeCtrl.text,
          facultyId: widget.faculty.id,
        );
        _nameCtrl.clear();
        _codeCtrl.clear();
      } else {
        await AdminService.assignSubject(subjectId: choice, facultyId: widget.faculty.id);
      }
      _changed = true;
      await _refreshSubjects();
      await _loadClassSubjects(classId);
    } catch (e) {
      debugPrint('Assign subject error: $e');
      final text = e.toString();
      if (mounted) {
        setState(() => _error = (text.contains('23505') || text.contains('duplicate'))
            ? 'This class already has a subject with that name. Pick it from the list instead.'
            : 'Could not save. Check your internet connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("${widget.faculty.name}'s Subjects"),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_subjects.isEmpty) const Text("No subjects assigned.", style: TextStyle(fontStyle: FontStyle.italic)),
              ..._subjects.map((sub) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("${sub.name} (${sub.code})", style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text("${sub.className}  |  ${sub.departmentName}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: "Remove from this teacher",
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                          onPressed: _busy ? null : () => _remove(sub),
                        ),
                      ],
                    ),
                  )),
              const Divider(height: 30),
              const Text("Assign a Subject:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _classId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: "Class", isDense: true, border: OutlineInputBorder()),
                items: _classes
                    .map((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['name'] as String)))
                    .toList(),
                onChanged: _busy ? null : (val) => val == null ? null : _loadClassSubjects(val),
              ),
              if (_classId != null) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: _subjectChoice,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: "Subject", isDense: true, border: OutlineInputBorder()),
                  items: [
                    ..._classSubjects.map((s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(
                            "${s.name} (${s.code})"
                            "${s.facultyId == widget.faculty.id ? ' - already theirs' : s.teacherName != null ? ' - now ${s.teacherName}' : ' - not assigned'}",
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                    const DropdownMenuItem(value: _newSubject, child: Text("+ New subject...")),
                  ],
                  onChanged: _busy ? null : (val) => setState(() => _subjectChoice = val),
                ),
                if (_subjectChoice == _newSubject) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nameCtrl,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: "Subject Name", hintText: "e.g. Operating Systems", isDense: true),
                  ),
                  TextField(
                    controller: _codeCtrl,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: "Subject Code", hintText: "e.g. CS-305", isDense: true),
                  ),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _assign,
                  icon: _busy
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add),
                  label: const Text("Assign Subject"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Removing a subject keeps its attendance and marks. Assigning a subject that belongs to another teacher moves it to this teacher.",
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _changed),
          child: const Text("Close"),
        ),
      ],
    );
  }
}

// ==========================================
// 7. HIERARCHICAL TIMETABLE PAGE
// ==========================================
class HierarchicalTimetablePage extends StatefulWidget {
  const HierarchicalTimetablePage({super.key});

  @override
  State<HierarchicalTimetablePage> createState() => _HierarchicalTimetablePageState();
}

class _HierarchicalTimetablePageState extends State<HierarchicalTimetablePage> {
  String? selectedDept;
  final List<String> departments = ['Computer Science', 'Mechanical Eng', 'Civil Eng', 'Commerce'];
  String? selectedRole;
  String? selectedEntityName;

  List<String> getAvailableNames() {
    if (selectedDept == null || selectedRole == null) return [];
    if (selectedRole == 'Faculty') {
      return allFaculty.where((f) => f['dept'] == selectedDept).map((f) => f['name'] as String).toList();
    } else {
      return allClasses.where((c) => c['dept'] == selectedDept).map((c) => c['className'] as String).toList();
    }
  }

  List<Map<String, String>> getCurrentSchedule() {
    if (selectedEntityName == null) return [];
    return timetableData[selectedEntityName] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFilterLabel("1. Select Department"),
                DropdownButtonFormField<String>(
                  value: selectedDept,
                  decoration: _inputDeco(),
                  items: departments.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (val) => setState(() { selectedDept = val; selectedRole = null; selectedEntityName = null; }),
                ),
                if (selectedDept != null) ...[
                  const SizedBox(height: 10),
                  _buildFilterLabel("2. Select Role"),
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    decoration: _inputDeco(),
                    items: const [DropdownMenuItem(value: 'Faculty', child: Text("Faculty (Assign Time)")), DropdownMenuItem(value: 'Students', child: Text("Students (View Class Time)"))],
                    onChanged: (val) => setState(() { selectedRole = val; selectedEntityName = null; }),
                  ),
                ],
                if (selectedRole != null) ...[
                  const SizedBox(height: 10),
                  _buildFilterLabel(selectedRole == 'Faculty' ? "3. Select Professor" : "3. Select Class"),
                  DropdownButtonFormField<String>(
                    value: selectedEntityName,
                    decoration: _inputDeco(),
                    items: getAvailableNames().map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                    onChanged: (val) => setState(() => selectedEntityName = val),
                  ),
                ]
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: selectedEntityName == null
                ? Center(child: Text("Select filters to view timetable", style: TextStyle(color: Colors.grey[600])))
                : _buildScheduleList(),
          ),
        ],
      ),
      floatingActionButton: (selectedRole == 'Faculty' && selectedEntityName != null)
          ? FloatingActionButton.extended(
        onPressed: _showAssignTimeDialog,
        backgroundColor: Colors.indigo,
        icon: const Icon(Icons.add_alarm),
        label: const Text("Add Slot"),
      )
          : null,
    );
  }

  Widget _buildFilterLabel(String text) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)));

  Widget _buildScheduleList() {
    final schedule = getCurrentSchedule();
    if (schedule.isEmpty) return Center(child: Text("No schedule found for $selectedEntityName"));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: schedule.length,
      itemBuilder: (ctx, i) {
        final item = schedule[i];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(5)), child: Text(item['time']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo))),
            title: Text(item['title']!, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(item['sub']!),
            trailing: selectedRole == 'Faculty' ? IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => schedule.removeAt(i))) : null,
          ),
        );
      },
    );
  }

  void _showAssignTimeDialog() {
    final timeCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    final detailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Add Slot for $selectedEntityName"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: timeCtrl, decoration: const InputDecoration(labelText: "Time")), TextField(controller: subjectCtrl, decoration: const InputDecoration(labelText: "Subject")), TextField(controller: detailCtrl, decoration: const InputDecoration(labelText: "Class / Room Detail"))]),
        actions: [ElevatedButton(onPressed: () { setState(() { if (!timetableData.containsKey(selectedEntityName)) timetableData[selectedEntityName!] = []; timetableData[selectedEntityName]!.add({'time': timeCtrl.text, 'title': subjectCtrl.text, 'sub': detailCtrl.text}); timetableData[selectedEntityName]!.sort((a,b) => a['time']!.compareTo(b['time']!)); }); Navigator.pop(ctx); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white), child: const Text("Save Slot"))],
      ),
    );
  }

  InputDecoration _inputDeco() => const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10), isDense: true);
}

// The Broadcast / Messages page now lives in communication_page.dart
