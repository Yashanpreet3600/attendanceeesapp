import 'dart:async';
import 'package:flutter/material.dart';
import 'attendance.dart'; // Ensure this file exists
import 'test.dart'; // Ensure this file exists
import 'main.dart'; // For logout navigation
import 'app_session.dart';
import 'leave_service.dart';
import 'academic_service.dart';
import 'message_service.dart';
import 'excel_export.dart';
import 'communication_page.dart';
import 'performance_page.dart';
import 'notification_service.dart';
import 'attachment_viewer.dart';
import 'password_dialog.dart';

class FacultyDashboard extends StatefulWidget {
  const FacultyDashboard({super.key});

  @override
  State<FacultyDashboard> createState() => _FacultyDashboardState();
}

class _FacultyDashboardState extends State<FacultyDashboard> {
  // --- BRANDING COLORS ---
  final Color kalgidharBlue = const Color(0xFF002046);
  final Color kalgidharTeal = const Color(0xFF00796B);
  final Color alertRed = const Color(0xFFD32F2F);

  // --- LOGGED-IN TEACHER (from Supabase) ---
  final AppUser? me = AppSession.currentUser;

  // --- LEAVE REQUESTS FROM STUDENTS (live from Supabase) ---
  final ValueNotifier<List<Map<String, dynamic>>> leaveRequests = ValueNotifier([]);
  final ValueNotifier<String?> leaveError = ValueNotifier(null);
  StreamSubscription<List<Map<String, dynamic>>>? _leaveSubscription;
  final Set<int> _knownLeaveIds = {};
  bool _firstLeaveLoad = true;

  // Classes this teacher is in-charge of (class teacher), for "My Class Performance"
  List<Map<String, dynamic>> _inchargeClasses = [];

  bool get _isHod => me?.designation == 'HOD';

  Future<void> _loadInchargeClasses() async {
    final teacher = me;
    if (teacher == null) return;
    try {
      final rows = await supabase
          .from('classes')
          .select('id, name')
          .eq('class_teacher_id', teacher.id)
          .order('name', ascending: true);
      if (mounted) setState(() => _inchargeClasses = rows);
    } catch (e) {
      debugPrint('Load in-charge classes error: $e');
    }
  }

  void _openMessages({int tab = 0}) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CommunicationPage(initialTab: tab)))
        .then((_) => _inbox?.refresh());
  }

  void _openDepartmentPerformance() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClassPerformancePage(
          departmentId: me?.departmentId,
          lockDepartment: true,
          title: "${me?.departmentName ?? 'Department'} Performance",
        ),
      ),
    );
  }

  void _openClassPerformance(Map<String, dynamic> cls) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClassPerformanceDetailPage(classId: cls['id'] as int, className: cls['name'] as String),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _startLeaveUpdates();
    _loadMySubjects();
    _startInbox();
    _loadInchargeClasses();
  }

  @override
  void dispose() {
    _leaveSubscription?.cancel();
    _inbox?.removeListener(_onInboxChanged);
    _inbox?.dispose();
    leaveRequests.dispose();
    leaveError.dispose();
    super.dispose();
  }

  void _startLeaveUpdates() {
    final teacher = me;
    if (teacher == null) return;

    _leaveSubscription = LeaveService.streamForTeacher(teacher.id).listen(
      (rows) {
        // Pop-up message when a NEW request arrives while the app is open
        if (!_firstLeaveLoad && mounted) {
          final newOnes = rows.where((l) => !_knownLeaveIds.contains(l['id'] as int) && l['status'] == 'Pending').toList();
          if (newOnes.isNotEmpty) {
            NotificationService.show(
              "New leave request",
              newOnes.length == 1
                  ? "From ${newOnes.first['student_name']} (${newOnes.first['student_roll']})"
                  : "${newOnes.length} new leave requests",
            );
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(newOnes.length == 1
                  ? "New leave request from ${newOnes.first['student_name']}"
                  : "${newOnes.length} new leave requests"),
              backgroundColor: kalgidharBlue,
              action: SnackBarAction(
                label: 'VIEW',
                textColor: Colors.white,
                onPressed: () => _showLeaveRequestsSheet(context),
              ),
            ));
          }
        }
        _firstLeaveLoad = false;
        _knownLeaveIds
          ..clear()
          ..addAll(rows.map((l) => l['id'] as int));

        leaveRequests.value = rows;
        leaveError.value = null;
      },
      onError: (Object e) {
        debugPrint('Leave stream error: $e');
        leaveError.value = 'Could not load leave requests. Check your internet connection.';
      },
    );
  }

  int _pendingCount(List<Map<String, dynamic>> leaves) =>
      leaves.where((l) => l['status'] == 'Pending').length;

  // --- STATE VARIABLES ---
  String selectedDepartment = 'Computer Science';
  String selectedClass = 'CS-A';
  String selectedSubject = 'Data Structures';

  // --- MOCK DATA ---

  // 1. Messages for this teacher (from the admin office), delivered like leave requests
  InboxController? _inbox;

  // Unread messages: used by the bell badge in the app bar
  List<InboxItem> get adminNotifications => _inbox?.items.where((i) => i.isUnread).toList() ?? [];

  void _startInbox() {
    final teacher = me;
    if (teacher == null) return;
    _inbox = InboxController(
      userId: teacher.id,
      onNewMessage: (item) {
        NotificationService.show("New message from ${item.fromLabel}", item.title);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("New message from ${item.fromLabel}: ${item.title}"),
          backgroundColor: kalgidharBlue,
          action: SnackBarAction(
            label: 'VIEW',
            textColor: Colors.white,
            onPressed: () => _openMessages(tab: 0),
          ),
        ));
      },
    )..start();
    _inbox!.addListener(_onInboxChanged);
  }

  void _onInboxChanged() {
    if (mounted) setState(() {});
  }

  // 2. Simulated Missed Classes (Triggered if time table match fails)
  // This list simulates classes where attendance wasn't uploaded on time.
  List<Map<String, dynamic>> missedClasses = [
    {
      'class': 'CS-B',
      'subject': 'Web Development',
      'time': '10:00 AM - 11:00 AM',
      'date': 'Today',
      'status': 'Missing Attendance'
    }
  ];

  // 3. Dropdown Data - built from the subjects assigned to this teacher
  //    in Supabase (department -> classes, class -> subjects)
  Map<String, List<String>> departmentData = {};
  Map<String, List<String>> subjectData = {};
  Map<String, SubjectInfo> _subjectLookup = {}; // 'CS-A|Data Structures' -> subject
  List<SubjectInfo> _mySubjects = [];
  bool _subjectsLoading = true;
  String? _subjectsError;
  bool _exporting = false;

  SubjectInfo? get _currentSubject => _subjectLookup['$selectedClass|$selectedSubject'];

  Future<void> _loadMySubjects() async {
    final teacher = me;
    if (teacher == null) return;
    setState(() {
      _subjectsLoading = true;
      _subjectsError = null;
    });
    try {
      final subjects = await AcademicService.loadFacultySubjects(teacher.id);
      if (!mounted) return;

      final depts = <String, List<String>>{};
      final subs = <String, List<String>>{};
      final lookup = <String, SubjectInfo>{};
      for (final sub in subjects) {
        final classes = depts.putIfAbsent(sub.departmentName, () => []);
        if (!classes.contains(sub.className)) classes.add(sub.className);
        subs.putIfAbsent(sub.className, () => []).add(sub.name);
        lookup['${sub.className}|${sub.name}'] = sub;
      }

      setState(() {
        departmentData = depts;
        subjectData = subs;
        _subjectLookup = lookup;
        _mySubjects = subjects;
        if (subjects.isNotEmpty) {
          selectedDepartment = subjects.first.departmentName;
          selectedClass = subjects.first.className;
          selectedSubject = subjects.first.name;
        }
        _subjectsLoading = false;
      });
    } catch (e) {
      debugPrint('Load subjects error: $e');
      if (mounted) {
        setState(() {
          _subjectsLoading = false;
          _subjectsError = 'Could not load your subjects. Check your internet connection.';
        });
      }
    }
  }

  void _showNoSubjectMessage() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Choose a class and subject first. If the list is empty, ask the admin to assign subjects to you."),
    ));
  }

  // 4. Stats
  final Map<String, Map<String, dynamic>> lectureStats = {
    'CS-A': {'scheduled': 45, 'delivered': 38, 'extra': 2},
    'CS-B': {'scheduled': 40, 'delivered': 30, 'extra': 0},
    'BCA': {'scheduled': 50, 'delivered': 45, 'extra': 5},
    'ME-A': {'scheduled': 42, 'delivered': 40, 'extra': 1},
    'ME-B': {'scheduled': 42, 'delivered': 35, 'extra': 0},
    'B.Com-I': {'scheduled': 60, 'delivered': 55, 'extra': 3},
    'BBA-I': {'scheduled': 55, 'delivered': 50, 'extra': 2},
  };

  final List<String> studentList = [
    'Rahul Kumar (101)', 'Sneha Gupta (102)', 'Amit Roy (103)', 'Priya Das (104)'
  ];

  @override
  Widget build(BuildContext context) {
    var stats = lectureStats[selectedClass] ?? {'scheduled': 0, 'delivered': 0, 'extra': 0};

    return Scaffold(
      backgroundColor: Colors.grey[50],
      drawer: _buildSideBar(context),
      appBar: AppBar(
        backgroundColor: kalgidharBlue,
        title: const Text('Faculty Dashboard', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // --- BELL NOTIFICATION ICON ---
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () => _openMessages(tab: 0),
              ),
              if (adminNotifications.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                    constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                    child: Text('${adminNotifications.length}', style: const TextStyle(color: Colors.white, fontSize: 8), textAlign: TextAlign.center),
                  ),
                )
            ],
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // --- 1. MISSED CLASS ALERT (NEW) ---
            if (missedClasses.isNotEmpty) ...[
              _buildSectionHeader("⚠️ Action Required"),
              Card(
                color: Colors.red[50],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: alertRed.withOpacity(0.3))),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: alertRed, size: 30),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Missed Class Detected!", style: TextStyle(fontWeight: FontWeight.bold, color: alertRed, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text("Attendance not uploaded for ${missedClasses[0]['class']} (${missedClasses[0]['subject']}) on time.", style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _showResolveMissedClassDialog(context, 0),
                          icon: const Icon(Icons.edit_note, size: 16),
                          label: const Text("Provide Reason"),
                          style: ElevatedButton.styleFrom(backgroundColor: alertRed, foregroundColor: Colors.white),
                        ),
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // --- PERFORMANCE (HOD: whole department, class in-charge: own class) ---
            if (_isHod || _inchargeClasses.isNotEmpty) ...[
              _buildSectionHeader(_isHod ? "Department (HOD)" : "My Class"),
              if (_isHod)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.insights, color: Colors.indigo),
                    ),
                    title: const Text("Department Performance"),
                    subtitle: Text("Attendance and Monday Tests of every class in ${me?.departmentName ?? 'your department'}"),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _openDepartmentPerformance,
                  ),
                ),
              ..._inchargeClasses.map((cls) => Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: kalgidharTeal.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.groups, color: kalgidharTeal),
                      ),
                      title: Text("My Class: ${cls['name']}"),
                      subtitle: const Text("Performance of every student in your class"),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => _openClassPerformance(cls),
                    ),
                  )),
              const SizedBox(height: 20),
            ],

            // --- LEAVE REQUESTS (live from Supabase) ---
            _buildSectionHeader("Leave Requests"),
            ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: leaveRequests,
              builder: (context, leaves, _) {
                final pending = _pendingCount(leaves);
                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.event_busy, color: Colors.orange[800]),
                    ),
                    title: const Text("Student Leave Requests"),
                    subtitle: Text(pending == 0
                        ? "No requests waiting"
                        : "$pending waiting for your review"),
                    trailing: pending == 0
                        ? const Icon(Icons.arrow_forward_ios, size: 16)
                        : CircleAvatar(
                            radius: 13,
                            backgroundColor: alertRed,
                            child: Text('$pending', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                    onTap: () => _showLeaveRequestsSheet(context),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            // --- 2. SELECTION FILTERS ---
            _buildSectionHeader("Class & Subject Selection"),
            _buildSubjectSelector(),
            const SizedBox(height: 20),

            // --- 3. LECTURE OVERVIEW ---
            _buildSectionHeader("Lecture Overview"),
            Row(
              children: [
                _buildStatBox("Scheduled", stats['scheduled'].toString(), Colors.blueGrey),
                const SizedBox(width: 10),
                _buildStatBox("Delivered", stats['delivered'].toString(), kalgidharBlue),
                const SizedBox(width: 10),
                _buildStatBox("Extra", stats['extra'].toString(), Colors.orange[800]!),
              ],
            ),
            const SizedBox(height: 20),

            // --- 4. COMMUNICATION ---
            _buildSectionHeader("Communication"),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.translate, color: Colors.blue),
                ),
                title: const Text("Messages"),
                subtitle: Text(adminNotifications.isEmpty
                    ? "Inbox, replies, and messages to students or the admin office"
                    : "${adminNotifications.length} unread  |  Tap to read and reply"),
                trailing: adminNotifications.isEmpty
                    ? const Icon(Icons.arrow_forward_ios, size: 16)
                    : CircleAvatar(
                        radius: 13,
                        backgroundColor: alertRed,
                        child: Text('${adminNotifications.length}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                onTap: () => _openMessages(tab: 1),
              ),
            ),
            const SizedBox(height: 20),

            // --- 5. DATA ENTRY & ACTIONS ---
            _buildSectionHeader("Data Entry & Actions"),
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    context, Icons.cloud_upload_outlined, 'Upload\nAttendance', kalgidharBlue,
                        () => _showUploadAttendanceDialog(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionButton(
                    context, Icons.post_add, 'Upload\nTest (17)', kalgidharTeal,
                        () => _showUploadTestDialog(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionButton(
                    context, Icons.add_alarm, 'Extra\nClass', Colors.orange[800]!,
                        () => _showExtraLectureDialog(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // --- 6. REPORTS ---
            _buildSectionHeader("Reports"),
            Row(
              children: [
                Expanded(child: _buildDownloadButton(context, "Attendance (Excel)", Icons.grid_on, Colors.green[700]!, () => _exportReport(attendance: true))),
                const SizedBox(width: 15),
                Expanded(child: _buildDownloadButton(context, "Monday Test (Excel)", Icons.assessment, kalgidharBlue, () => _exportReport(attendance: false))),
              ],
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // SIDEBAR
  // ==========================================
  Widget _buildSideBar(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: kalgidharBlue),
            accountName: Text(me?.fullName ?? 'Faculty'),
            accountEmail: Text("Faculty ID: ${me?.loginId ?? '-'}${me?.designation != null ? '  |  ${me!.designation}' : ''}"),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 40, color: Color(0xFF002046)),
            ),
          ),
          ListTile(
            leading: Icon(Icons.dashboard, color: kalgidharBlue),
            title: const Text("Dashboard"),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: Icon(Icons.calendar_month, color: kalgidharBlue),
            title: const Text("Time Table"),
            onTap: () {
              Navigator.pop(context);
              _showTimeTable(context);
            },
          ),
          ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: leaveRequests,
            builder: (context, leaves, _) {
              final pending = _pendingCount(leaves);
              return ListTile(
                leading: Icon(Icons.event_busy, color: kalgidharBlue),
                title: const Text("Leave Requests"),
                trailing: pending == 0
                    ? null
                    : CircleAvatar(
                        radius: 11,
                        backgroundColor: alertRed,
                        child: Text('$pending', style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                onTap: () {
                  Navigator.pop(context);
                  _showLeaveRequestsSheet(this.context);
                },
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.forum, color: kalgidharBlue),
            title: const Text("Messages"),
            trailing: adminNotifications.isEmpty
                ? null
                : CircleAvatar(
                    radius: 11,
                    backgroundColor: alertRed,
                    child: Text('${adminNotifications.length}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
            onTap: () {
              Navigator.pop(context);
              _openMessages(tab: 0);
            },
          ),
          if (_isHod)
            ListTile(
              leading: Icon(Icons.insights, color: kalgidharBlue),
              title: const Text("Department Performance"),
              onTap: () {
                Navigator.pop(context);
                _openDepartmentPerformance();
              },
            ),
          ListTile(
            leading: Icon(Icons.lock_outline, color: kalgidharBlue),
            title: const Text("Change Password"),
            onTap: () {
              Navigator.pop(context);
              showChangePasswordDialog(this.context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("Logout", style: TextStyle(color: Colors.red)),
            onTap: () {
              AppSession.signOut();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => LoginScreen()),
                (Route<dynamic> route) => false,
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // DIALOGS & LOGIC
  // ==========================================

  // --- LEAVE REQUESTS SHEET (live) ---
  // Pending requests at the top with Approve / Reject.
  // When the teacher decides, the card moves to "Reviewed" by itself.
  void _showLeaveRequestsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Student Leave Requests", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kalgidharBlue)),
              const Text("New requests appear here automatically.", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const Divider(),
              ValueListenableBuilder<String?>(
                valueListenable: leaveError,
                builder: (context, error, _) => error == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(error, style: const TextStyle(color: Colors.red)),
                      ),
              ),
              Expanded(
                child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: leaveRequests,
                  builder: (context, leaves, _) {
                    if (leaves.isEmpty) {
                      return const Center(
                        child: Text("No leave requests yet. Requests from your students will show up here.",
                            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                      );
                    }

                    final pending = leaves.where((l) => l['status'] == 'Pending').toList();
                    final reviewed = leaves.where((l) => l['status'] != 'Pending').toList();

                    return ListView(
                      children: [
                        Text("Pending (${pending.length})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        if (pending.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text("All caught up. No requests are waiting.", style: TextStyle(color: Colors.green)),
                          ),
                        ...pending.map((l) => _buildLeaveRequestCard(l)),
                        if (reviewed.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text("Reviewed (${reviewed.length})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          ...reviewed.map((l) => _buildLeaveRequestCard(l)),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeaveRequestCard(Map<String, dynamic> leave) {
    final String status = leave['status'] as String;
    final String? remark = leave['remark'] as String?;
    final bool isPending = status == 'Pending';
    final Color statusColor = status == 'Approved'
        ? Colors.green
        : status == 'Rejected'
            ? alertRed
            : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "${leave['student_name']} (${leave['student_roll']})",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            if (leave['class_name'] != null)
              Text("Class: ${leave['class_name']}  |  Sent to you as ${leave['sent_to']}",
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const Divider(),
            _buildLeaveDetail(Icons.date_range, LeaveService.formatRange(leave)),
            _buildLeaveDetail(Icons.notes, leave['reason'] as String),
            if (leave['attachment_path'] != null)
              LeaveAttachmentButton(path: leave['attachment_path'] as String),
            if (!isPending && remark != null && remark.isNotEmpty)
              _buildLeaveDetail(Icons.comment_outlined, "Your remark: $remark"),
            if (isPending) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showReviewLeaveDialog(leave, approve: false),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text("Reject"),
                      style: OutlinedButton.styleFrom(foregroundColor: alertRed, side: BorderSide(color: alertRed)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showReviewLeaveDialog(leave, approve: true),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text("Approve"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveDetail(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey[700]),
          const SizedBox(width: 6),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  // Approve / Reject with an optional remark the student will see
  void _showReviewLeaveDialog(Map<String, dynamic> leave, {required bool approve}) {
    final remarkController = TextEditingController();
    bool isSaving = false;
    String? saveError;
    final Color actionColor = approve ? Colors.green[700]! : alertRed;
    final String actionLabel = approve ? "Approve" : "Reject";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text("$actionLabel Leave", style: TextStyle(color: actionColor, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${leave['student_name']} (${leave['student_roll']})", style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(LeaveService.formatRange(leave), style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 15),
              TextField(
                controller: remarkController,
                enabled: !isSaving,
                maxLines: 2,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: approve ? "Remark (optional), e.g. Take care" : "Reason for rejecting (optional)",
                  border: const OutlineInputBorder(),
                ),
              ),
              if (saveError != null)
                Text(saveError!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: actionColor),
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() {
                        isSaving = true;
                        saveError = null;
                      });
                      try {
                        await LeaveService.review(
                          leaveId: leave['id'] as int,
                          approve: approve,
                          remark: remarkController.text,
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        debugPrint('Review leave error: $e');
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          isSaving = false;
                          saveError = "Could not save. Check your internet connection and try again.";
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(actionLabel, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // --- 1. ADMIN NOTIFICATIONS DIALOG ---
  // --- 2. MISSED CLASS RESOLUTION DIALOG (Reason + Camera) ---
  void _showResolveMissedClassDialog(BuildContext context, int index) {
    final reasonController = TextEditingController();
    bool imageAttached = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text("Explain Absence", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Why was the attendance not uploaded?", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      TextField(
                        controller: reasonController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: "e.g., On Leave, Technical Issue, OD...",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 15),
                      const Text("Attach Proof (Optional):", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() => imageAttached = !imageAttached);
                        },
                        icon: Icon(imageAttached ? Icons.check : Icons.camera_alt),
                        label: Text(imageAttached ? "Photo Attached" : "Open Camera"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: imageAttached ? Colors.green : Colors.grey[200],
                          foregroundColor: imageAttached ? Colors.white : Colors.black,
                        ),
                      )
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: kalgidharBlue, foregroundColor: Colors.white),
                    onPressed: () {
                      if (reasonController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a reason."), backgroundColor: Colors.red));
                        return;
                      }
                      // Resolve logic
                      Navigator.pop(ctx);
                      setState(() {
                        missedClasses.removeAt(index);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Explanation Submitted to Admin."), backgroundColor: Colors.green));
                    },
                    child: const Text("Submit"),
                  )
                ],
              );
            }
        );
      },
    );
  }

  // --- 3. EXTRA LECTURE DIALOG ---
  void _showExtraLectureDialog(BuildContext context) {
    final dateController = TextEditingController(text: "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}");
    final timeController = TextEditingController();
    final roomController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Mark Extra Lecture", style: TextStyle(color: kalgidharBlue)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: dateController, decoration: const InputDecoration(labelText: "Date", hintText: "DD/MM/YYYY", prefixIcon: Icon(Icons.calendar_today))),
              TextField(controller: timeController, decoration: const InputDecoration(labelText: "Timing", hintText: "e.g. 10:00 AM", prefixIcon: Icon(Icons.access_time))),
              TextField(controller: roomController, decoration: const InputDecoration(labelText: "Room No", hintText: "e.g. LT-1", prefixIcon: Icon(Icons.meeting_room))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white),
            onPressed: () {
              if (dateController.text.isEmpty || timeController.text.isEmpty || roomController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All fields are required"), backgroundColor: Colors.red));
                return;
              }
              setState(() {
                lectureStats[selectedClass]!['extra'] += 1;
                lectureStats[selectedClass]!['delivered'] += 1;
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Extra Lecture Added!"), backgroundColor: Colors.green));
            },
            child: const Text("Confirm"),
          )
        ],
      ),
    );
  }

  // --- 4. MESSAGE DIALOG ---
  // ==========================================
  // WIDGET HELPERS
  // ==========================================

  Widget _buildStatBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
            boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(padding: const EdgeInsets.only(bottom: 10, top: 5), child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])));
  }

  Widget _buildDropdown({required String value, required List<String> items, required Function(String?) onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: value, isExpanded: true, icon: Icon(Icons.arrow_drop_down, color: kalgidharBlue), onChanged: onChanged, items: items.map((item) => DropdownMenuItem(value: item, child: Text(item, overflow: TextOverflow.ellipsis))).toList())),
    );
  }

  Widget _actionButton(BuildContext context, IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
        onTap: onTap,
        child: Container(
            height: 85,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.3))
            ),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 26, color: color),
                  const SizedBox(height: 4),
                  Text(label, textAlign: TextAlign.center, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11))
                ]
            )
        )
    );
  }

  Widget _buildDownloadButton(BuildContext context, String label, IconData icon, Color color, VoidCallback onPressed) {
    return ElevatedButton(
        onPressed: _exporting ? null : onPressed,
        style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white, foregroundColor: color, elevation: 2,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withOpacity(0.1)))
        ),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Icon(icon, size: 20), const SizedBox(width: 8), Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))]
        )
    );
  }

  // --- OTHERS ---
  void _showTimeTable(BuildContext context) {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => const SizedBox(height: 200, child: Center(child: Text("Time Table Placeholder"))));
  }

  void _showUploadTestDialog(BuildContext context) {
    final subject = _currentSubject;
    if (subject == null) {
      _showNoSubjectMessage();
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => MarkTestScreen(subject: subject)));
  }

  void _showUploadAttendanceDialog(BuildContext context) {
    final subject = _currentSubject;
    if (subject == null) {
      _showNoSubjectMessage();
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => MarkAttendanceScreen(subject: subject)));
  }

  // --- EXCEL REPORTS ---
  Future<void> _exportReport({required bool attendance}) async {
    final subject = _currentSubject;
    if (subject == null) {
      _showNoSubjectMessage();
      return;
    }
    if (_exporting) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    messenger.showSnackBar(SnackBar(
      content: Text("Preparing ${attendance ? 'attendance' : 'Monday Test'} Excel file for ${subject.label}..."),
      duration: const Duration(seconds: 2),
    ));

    try {
      final result = attendance
          ? await ExcelExport.attendanceReport(subject: subject, facultyName: me?.fullName ?? '')
          : await ExcelExport.mondayTestReport(subject: subject, facultyName: me?.fullName ?? '');
      if (!mounted) return;
      messenger.hideCurrentSnackBar();

      if (result.noData) {
        messenger.showSnackBar(SnackBar(
          content: Text(attendance
              ? "No attendance has been uploaded for ${subject.label} yet."
              : "No Monday Test marks have been uploaded for ${subject.label} yet."),
          backgroundColor: Colors.orange[800],
        ));
      } else if (result.saved) {
        messenger.showSnackBar(SnackBar(
          content: Text("Excel file saved to ${result.location}."),
          backgroundColor: Colors.green[700],
        ));
      }
    } catch (e) {
      debugPrint('Excel export error: $e');
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(
        content: Text("Could not create the Excel file. Check your internet connection and try again."),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // --- CLASS & SUBJECT SELECTOR (subjects from Supabase) ---
  Widget _buildSubjectSelector() {
    if (_subjectsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      );
    }
    if (_subjectsError != null) {
      return Card(
        color: Colors.red[50],
        child: ListTile(
          leading: Icon(Icons.wifi_off, color: alertRed),
          title: Text(_subjectsError!, style: const TextStyle(fontSize: 13)),
          trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _loadMySubjects),
        ),
      );
    }
    if (_mySubjects.isEmpty) {
      return Card(
        color: Colors.orange[50],
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            "No subjects are assigned to you yet. Ask the admin to add your subjects in Supabase (subjects table, faculty ID ${me?.loginId ?? ''}).",
            style: const TextStyle(fontSize: 13),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
            Row(
              children: [
                Expanded(
                  child: _buildDropdown(
                    value: selectedDepartment,
                    items: departmentData.keys.toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedDepartment = val!;
                        selectedClass = departmentData[val]!.first;
                        selectedSubject = subjectData[selectedClass]!.first;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildDropdown(
                    value: selectedClass,
                    items: departmentData[selectedDepartment]!,
                    onChanged: (val) => setState(() {
                      selectedClass = val!;
                      selectedSubject = subjectData[selectedClass]!.first;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kalgidharBlue.withOpacity(0.5))
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedSubject,
                  isExpanded: true,
                  icon: Icon(Icons.book, color: kalgidharBlue),
                  onChanged: (val) => setState(() => selectedSubject = val!),
                  items: subjectData[selectedClass]!.map((item) => DropdownMenuItem(value: item, child: Text(item, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: kalgidharBlue)))).toList(),
                ),
              ),
            ),
      ],
    );
  }

}