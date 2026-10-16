import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'main.dart';
import 'app_session.dart';
import 'leave_service.dart';
import 'academic_service.dart';
import 'message_service.dart';
import 'message_thread_page.dart';
import 'notification_service.dart';
import 'attachment_viewer.dart';
import 'password_dialog.dart';
// --- ENTRY POINT ---


// --- STUDENT DASHBOARD CODE ---
class StudentDashboard extends StatefulWidget {
  @override
  _StudentDashboardState createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  // --- BRANDING COLORS ---
  final Color kalgidharBlue = const Color(0xFF002046);
  final Color kalgidharTeal = const Color(0xFF00796B);

  // --- STATE ---
  String selectedSubjectCode = 'MAT-101';

  // --- DATA: MESSAGES FROM FACULTY / ADMIN (live from Supabase) ---
  // Delivered like leave requests: each student gets their own copy,
  // can mark it read and reply to the teacher / admin.
  InboxController? _inbox;

  // --- LOGGED-IN STUDENT (from Supabase) ---
  final AppUser? me = AppSession.currentUser;

  // --- DATA: LEAVE REQUESTS (live from Supabase) ---
  final ValueNotifier<List<Map<String, dynamic>>> myLeaves = ValueNotifier([]);
  final ValueNotifier<String?> leaveError = ValueNotifier(null);
  StreamSubscription<List<Map<String, dynamic>>>? _leaveSubscription;
  final Map<int, String> _lastLeaveStatus = {};
  bool _firstLeaveLoad = true;

  // Teachers this student can send leave to (class in-charge, HOD)
  List<LeaveRecipient> _leaveRecipients = [];
  bool _recipientsLoaded = false;

  @override
  void initState() {
    super.initState();
    _startLeaveUpdates();
    _loadLeaveRecipients();
    _loadAcademicData();
    _startMessages();
  }

  @override
  void dispose() {
    _leaveSubscription?.cancel();
    _inbox?.removeListener(_onInboxChanged);
    _inbox?.dispose();
    myLeaves.dispose();
    leaveError.dispose();
    super.dispose();
  }

  void _startLeaveUpdates() {
    final student = me;
    if (student == null) return;

    _leaveSubscription = LeaveService.streamForStudent(student.id).listen(
      (rows) {
        // Tell the student when a teacher approves or rejects a request
        if (!_firstLeaveLoad) {
          for (final leave in rows) {
            final id = leave['id'] as int;
            final oldStatus = _lastLeaveStatus[id];
            final newStatus = leave['status'] as String;
            if (oldStatus == 'Pending' && newStatus != 'Pending' && mounted) {
              NotificationService.show(
                "Leave $newStatus",
                "Your leave for ${LeaveService.formatDbDate(leave['from_date'])} was ${newStatus.toLowerCase()} by ${leave['teacher_name']}.",
              );
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text("Your leave for ${LeaveService.formatDbDate(leave['from_date'])} was ${newStatus.toLowerCase()} by ${leave['teacher_name']}."),
                backgroundColor: newStatus == 'Approved' ? Colors.green : Colors.red,
              ));
            }
          }
        }
        _firstLeaveLoad = false;
        _lastLeaveStatus
          ..clear()
          ..addEntries(rows.map((l) => MapEntry(l['id'] as int, l['status'] as String)));

        myLeaves.value = rows;
        leaveError.value = null;
      },
      onError: (Object e) {
        debugPrint('Leave stream error: $e');
        leaveError.value = 'Could not load your leave requests. Check your internet connection.';
      },
    );
  }

  Future<void> _loadLeaveRecipients() async {
    final student = me;
    if (student == null) return;
    try {
      final recipients = await LeaveService.loadRecipients(student);
      if (!mounted) return;
      setState(() {
        _leaveRecipients = recipients;
        _recipientsLoaded = true;
      });
    } catch (e) {
      debugPrint('Could not load leave recipients: $e');
    }
  }

  // --- DATA: SUBJECTS, ATTENDANCE, MONDAY TESTS (loaded from Supabase) ---
  // Same shapes as before, so the cards below work unchanged:
  //   allSubjects:    [{name, code, total, attended}]
  //   attendanceLogs: code -> [{date, status}]
  //   testScores:     code -> [{test, score, absent, max}]
  List<Map<String, dynamic>> allSubjects = [];
  Map<String, List<Map<String, String>>> attendanceLogs = {};
  Map<String, List<Map<String, dynamic>>> testScores = {};
  bool _academicLoading = true;
  String? _academicError;

  Future<void> _loadAcademicData() async {
    final student = me;
    if (student == null) return;
    setState(() {
      _academicLoading = true;
      _academicError = null;
    });
    try {
      final data = await AcademicService.loadStudentData(student);
      if (!mounted) return;
      setState(() {
        allSubjects = data.subjects;
        attendanceLogs = data.attendanceLogs;
        testScores = data.testScores;
        if (allSubjects.isNotEmpty && !allSubjects.any((sub) => sub['code'] == selectedSubjectCode)) {
          selectedSubjectCode = allSubjects.first['code'] as String;
        }
        _academicLoading = false;
      });
    } catch (e) {
      debugPrint('Load academic data error: $e');
      if (mounted) {
        setState(() {
          _academicLoading = false;
          _academicError = 'Could not load attendance and marks. Pull down to try again.';
        });
      }
    }
  }

  void _startMessages() {
    final student = me;
    if (student == null) return;
    _inbox = InboxController(
      userId: student.id,
      onNewMessage: (item) {
        NotificationService.show("New message from ${item.fromLabel}", item.title);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("New message from ${item.fromLabel}: ${item.title}"),
          backgroundColor: kalgidharBlue,
          action: SnackBarAction(
            label: 'VIEW',
            textColor: Colors.white,
            onPressed: () => _showMessageCenter(context),
          ),
        ));
      },
    )..start();
    _inbox!.addListener(_onInboxChanged);
  }

  void _onInboxChanged() {
    if (mounted) setState(() {});
  }

  static String _fmtScore(dynamic v) {
    final d = (v as num?)?.toDouble() ?? 0;
    return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(1);
  }

  Widget _buildNoSubjectsCard() {
    return Card(
      color: Colors.orange[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _academicLoading
              ? "Loading your subjects..."
              : "No subjects are set up for your class yet. Your attendance and Monday Test marks will appear here once your teachers start uploading them.",
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  // --- DATA: TIMETABLE ---
  final List<Map<String, String>> timeTable = [
    {'time': '09:00 - 10:00', 'subject': 'Mathematics (MAT-101)', 'room': '201'},
    {'time': '10:00 - 11:00', 'subject': 'Physics (PHY-301)', 'room': 'Lab 2'},
    {'time': '11:00 - 11:30', 'subject': 'Break', 'room': '-'},
    {'time': '11:30 - 12:30', 'subject': 'Computer Science (CS-202)', 'room': 'Lab 1'},
    {'time': '12:30 - 01:30', 'subject': 'English (ENG-104)', 'room': '203'},
  ];

  @override
  Widget build(BuildContext context) {
    // Calculations
    final bool hasSubjects = allSubjects.isNotEmpty;
    final Map<String, dynamic> currentSubjectData = hasSubjects
        ? allSubjects.firstWhere((e) => e['code'] == selectedSubjectCode, orElse: () => allSubjects.first)
        : <String, dynamic>{'name': '', 'code': '', 'total': 0, 'attended': 0};
    final String currentCode = currentSubjectData['code'] as String;
    double subPercentage = currentSubjectData['total'] == 0 ? 0.0 : currentSubjectData['attended'] / currentSubjectData['total'];

    List<Map<String, dynamic>> subjectTests = testScores[currentCode] ?? [];
    final takenTests = subjectTests.where((t) => t['absent'] != true).toList(); // absent tests don't count
    double totalScoreSum = 0;
    for (var t in takenTests) totalScoreSum += t['score'];
    double averageScore = takenTests.isEmpty ? 0.0 : totalScoreSum / takenTests.length;
    double testPercentage = (averageScore / 17.0).clamp(0.0, 1.0).toDouble();

    int overallTotal = 0;
    int overallAttended = 0;
    for (var sub in allSubjects) {
      overallTotal += sub['total'] as int;
      overallAttended += sub['attended'] as int;
    }
    double overallPercentage = overallTotal == 0 ? 0 : overallAttended / overallTotal;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      drawer: _buildSideBar(context),
      appBar: AppBar(
        backgroundColor: kalgidharBlue,
        title: const Text('AttendEase Student', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: () => _showWarnings(context) // Updated function name
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAcademicData,
        child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome & Apply Leave
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Hello, ${me?.fullName ?? 'Student'}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(
                        "Roll No: ${me?.loginId ?? '-'}${me?.className != null ? '  |  ${me!.className}' : ''}",
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _showApplyLeaveDialog(context),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text("Apply Leave"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[700], foregroundColor: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _buildSectionTitle("Academic Overview"),
            if (_academicLoading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
            if (_academicError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_academicError!, style: const TextStyle(color: Colors.red)),
              ),
            _buildAttendanceCard("Overall Attendance", "All Subjects", overallPercentage, overallAttended, overallTotal, true),

            const SizedBox(height: 25), const Divider(), const SizedBox(height: 10),

            _buildSectionTitle("Subject Details"),
            if (!hasSubjects)
              _buildNoSubjectsCard()
            else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kalgidharBlue.withOpacity(0.3))),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: currentCode,
                  isExpanded: true,
                  onChanged: (val) => setState(() => selectedSubjectCode = val!),
                  items: allSubjects.map((s) => DropdownMenuItem(value: s['code'] as String, child: Text("${s['code']} - ${s['name']}"))).toList(),
                ),
              ),
            ),
            const SizedBox(height: 15),

            _buildAttendanceCard("Subject Attendance", currentSubjectData['name'], subPercentage, currentSubjectData['attended'], currentSubjectData['total'], false),

            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => _showAttendanceLogSheet(context, currentSubjectData['name']),
                icon: const Icon(Icons.calendar_month, size: 18),
                label: const Text("View Day-by-Day Attendance"),
                style: TextButton.styleFrom(foregroundColor: kalgidharBlue),
              ),
            ),

            const SizedBox(height: 10),

            _buildTestPerformanceCard(currentSubjectData['name'], averageScore, testPercentage),

            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => _showTestLogSheet(context, currentSubjectData['name'], subjectTests),
                icon: const Icon(Icons.assignment, size: 18),
                label: const Text("View All Test Scores"),
                style: TextButton.styleFrom(foregroundColor: Colors.deepPurple),
              ),
            ),

            ],
            const SizedBox(height: 20),

            Card(
              color: const Color(0xFFE3F2FD),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: Icon(Icons.mail_outline, color: kalgidharBlue),
                title: const Text("Faculty & Admin Messages"),
                subtitle: Text(_messagesSubtitle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: (_inbox?.unreadCount ?? 0) > 0
                    ? CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.red,
                        child: Text('${_inbox!.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      )
                    : Icon(Icons.arrow_forward, color: kalgidharBlue),
                onTap: () => _showMessageCenter(context),
              ),
            )
          ],
        ),
      ),
      ),
    );
  }

  // ==========================================
  // SIDEBAR (DRAWER)
  // ==========================================
  Widget _buildSideBar(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: kalgidharBlue),
            accountName: Text(me?.fullName ?? 'Student'),
            accountEmail: Text("Roll No: ${me?.loginId ?? '-'}${me?.className != null ? '  |  ${me!.className}' : ''}"),
            currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.person, size: 40, color: Color(0xFF002046))),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_outlined), title: const Text("Dashboard"),
            onTap: () => Navigator.pop(context),
          ),

          // --- UPDATED: Timetable in Sidebar ---
          ListTile(
            leading: const Icon(Icons.calendar_view_day_outlined), title: const Text("Timetable"),
            onTap: () {
              Navigator.pop(context);
              _showTimeTableSheet(context);
            },
          ),

          ListTile(
            leading: const Icon(Icons.fact_check_outlined), title: const Text("Leave Status"),
            onTap: () {
              Navigator.pop(context);
              _showLeaveStatusSheet(context);
            },
          ),

          // --- UPDATED: Renamed to Notifications (No SMS) ---
          ListTile(
            leading: const Icon(Icons.notifications_none, color: Colors.orange),
            title: const Text("Notifications"),
            onTap: () {
              Navigator.pop(context);
              _showWarnings(context);
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
            leading: const Icon(Icons.logout, color: Colors.red), title: const Text("Logout", style: TextStyle(color: Colors.red)),
            onTap: () {
              AppSession.signOut();
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => LoginScreen()),
                      (Route<dynamic> route) => false
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // UPDATED: WARNINGS (Removed Parent SMS)
  // ==========================================
  void _showWarnings(BuildContext context) {
    List<Map<String, dynamic>> lowAttendanceSubjects = allSubjects.where((sub) {
      if ((sub['total'] as int) == 0) return false; // no lectures yet
      double pct = sub['attended'] / sub['total'];
      return pct < 0.75;
    }).toList();

    List<String> lowMarkSubjects = [];
    testScores.forEach((key, tests) {
      for (var t in tests) {
        if (t['absent'] != true && t['score'] < 8.5) {
          lowMarkSubjects.add("$key (${t['test']})");
        }
      }
    });

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Alerts & Warnings", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kalgidharBlue)),
              const Text("Items requiring your immediate attention.", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    if (lowAttendanceSubjects.isEmpty && lowMarkSubjects.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Center(child: Text("No alerts! You are doing great.", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                      ),

                    ...lowAttendanceSubjects.map((sub) => _buildAlertTile(
                        "Low Attendance: ${sub['name']}",
                        "Current: ${(sub['attended']/sub['total']*100).toInt()}%. Required: 75%",
                        Icons.warning, Colors.red
                    )),

                    ...lowMarkSubjects.map((sub) => _buildAlertTile(
                        "Score Improvement Needed",
                        "Subject: $sub. Score is below 50%.",
                        Icons.trending_down, Colors.orange
                    )),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAlertTile(String title, String subtitle, IconData icon, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: color.withOpacity(0.1),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: color.withOpacity(0.3))),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        subtitle: Text(subtitle),
      ),
    );
  }

  // ==========================================
  // UPDATED: TIMETABLE SHEET
  // ==========================================
  void _showTimeTableSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Daily Timetable", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kalgidharBlue)),
                  Chip(label: Text("Wednesday"), backgroundColor: Colors.blue[100]),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView.separated(
                  itemCount: timeTable.length,
                  separatorBuilder: (c, i) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    var item = timeTable[i];
                    bool isBreak = item['subject'] == 'Break';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: isBreak ? Colors.orange[100] : Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                        child: Text(item['time']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      title: Text(item['subject']!, style: TextStyle(fontWeight: FontWeight.bold, color: isBreak ? Colors.orange : Colors.black87)),
                      trailing: Text(item['room']!, style: const TextStyle(color: Colors.grey)),
                    );
                  },
                ),
              )
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // APPLY LEAVE (saved to Supabase)
  // ==========================================
  void _showApplyLeaveDialog(BuildContext context) {
    final student = me;
    if (student == null) return;

    if (!_recipientsLoaded) {
      _loadLeaveRecipients();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Loading your teachers. Try again in a moment.")),
      );
      return;
    }
    if (_leaveRecipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No class in-charge or HOD is set for your class yet. Please contact the admin office.")),
      );
      return;
    }

    LeaveRecipient selectedRecipient = _leaveRecipients.first;
    DateTime? fromDate;
    DateTime? toDate;
    final fromController = TextEditingController();
    final toController = TextEditingController();
    final reasonController = TextEditingController();
    Uint8List? attachment; // photo of medical certificate (optional)
    bool isSending = false;
    String? formError;

    final DateTime today = DateTime.now();
    final DateTime earliest = today.subtract(const Duration(days: 30));
    final DateTime latest = today.add(const Duration(days: 365));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: Text("Apply for Leave", style: TextStyle(color: kalgidharBlue, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<LeaveRecipient>(
                      value: selectedRecipient,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Send To', border: OutlineInputBorder()),
                      items: _leaveRecipients
                          .map((r) => DropdownMenuItem(value: r, child: Text(r.label, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: isSending ? null : (val) => setDialogState(() => selectedRecipient = val!),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: fromController,
                      readOnly: true,
                      decoration: const InputDecoration(labelText: 'From Date', prefixIcon: Icon(Icons.calendar_today), border: OutlineInputBorder()),
                      onTap: isSending
                          ? null
                          : () async {
                              final picked = await showDatePicker(
                                context: dialogContext,
                                initialDate: fromDate ?? today,
                                firstDate: earliest,
                                lastDate: latest,
                              );
                              if (picked != null && dialogContext.mounted) {
                                setDialogState(() {
                                  fromDate = picked;
                                  fromController.text = LeaveService.formatDate(picked);
                                  // Keep "To" on or after "From"
                                  if (toDate == null || toDate!.isBefore(picked)) {
                                    toDate = picked;
                                    toController.text = LeaveService.formatDate(picked);
                                  }
                                });
                              }
                            },
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: toController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'To Date',
                        helperText: 'Same as From Date for a one-day leave',
                        prefixIcon: Icon(Icons.event),
                        border: OutlineInputBorder(),
                      ),
                      onTap: isSending
                          ? null
                          : () async {
                              final start = fromDate ?? today;
                              final picked = await showDatePicker(
                                context: dialogContext,
                                initialDate: toDate ?? start,
                                firstDate: start.isBefore(earliest) ? earliest : start,
                                lastDate: latest,
                              );
                              if (picked != null && dialogContext.mounted) {
                                setDialogState(() {
                                  toDate = picked;
                                  toController.text = LeaveService.formatDate(picked);
                                });
                              }
                            },
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: reasonController,
                      enabled: !isSending,
                      maxLines: 2,
                      maxLength: 300,
                      decoration: const InputDecoration(labelText: "Reason", border: OutlineInputBorder()),
                    ),

                    const SizedBox(height: 5),

                    // --- PHOTO ATTACHMENT (uploaded to Supabase Storage) ---
                    if (attachment == null)
                      InkWell(
                        onTap: isSending
                            ? null
                            : () async {
                                final bytes = await _pickLeavePhoto(dialogContext);
                                if (bytes != null && dialogContext.mounted) {
                                  setDialogState(() => attachment = bytes);
                                }
                              },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt, color: Colors.grey[700]),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  "Attach Photo / Medical Cert (optional)",
                                  style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          border: Border.all(color: Colors.green),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(attachment!, width: 56, height: 56, fit: BoxFit.cover),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text("Photo attached",
                                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                            ),
                            IconButton(
                              tooltip: "Remove photo",
                              onPressed: isSending ? null : () => setDialogState(() => attachment = null),
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                            ),
                          ],
                        ),
                      ),

                    if (formError != null) ...[
                      const SizedBox(height: 12),
                      Text(formError!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSending ? null : () => Navigator.pop(dialogContext),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: kalgidharBlue),
                  onPressed: isSending
                      ? null
                      : () async {
                          if (fromDate == null) {
                            setDialogState(() => formError = "Choose the date of your leave.");
                            return;
                          }
                          if (reasonController.text.trim().isEmpty) {
                            setDialogState(() => formError = "Write the reason for your leave.");
                            return;
                          }

                          setDialogState(() {
                            isSending = true;
                            formError = null;
                          });

                          try {
                            await LeaveService.applyLeave(
                              student: student,
                              recipient: selectedRecipient,
                              fromDate: fromDate!,
                              toDate: toDate ?? fromDate!,
                              reason: reasonController.text,
                              attachment: attachment,
                            );
                            if (!mounted || !dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(
                              content: Text("Leave request sent to ${selectedRecipient.teacherName}."),
                              backgroundColor: Colors.green,
                            ));
                          } catch (e) {
                            debugPrint('Apply leave error: $e');
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              isSending = false;
                              final text = e.toString();
                              formError = (text.contains('Bucket') || text.contains('attachment_path') || text.contains('bucket'))
                                  ? "Photo upload isn't set up yet. Ask the admin to run supabase_phase5.sql, or remove the photo and send."
                                  : "Could not send your request. Check your internet connection and try again.";
                            });
                          }
                        },
                  child: isSending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text("Send Request", style: TextStyle(color: Colors.white)),
                )
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // HELPERS (Leave Status, Message Center, Cards)
  // ==========================================

  // Live list: updates by itself when a teacher approves or rejects
  void _showLeaveStatusSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Leave Application Status", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kalgidharBlue)),
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
                  valueListenable: myLeaves,
                  builder: (context, leaves, _) {
                    if (leaves.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text("You haven't applied for leave yet.", style: TextStyle(color: Colors.grey)),
                            const SizedBox(height: 10),
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showApplyLeaveDialog(this.context);
                              },
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text("Apply Leave"),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: leaves.length,
                      itemBuilder: (ctx, i) {
                        final item = leaves[i];
                        final String status = item['status'] as String;
                        final String? remark = item['remark'] as String?;
                        Color statusColor;
                        IconData statusIcon;

                        if (status == 'Approved') {
                          statusColor = Colors.green;
                          statusIcon = Icons.check_circle_outline;
                        } else if (status == 'Rejected') {
                          statusColor = Colors.red;
                          statusIcon = Icons.cancel_outlined;
                        } else {
                          statusColor = Colors.orange;
                          statusIcon = Icons.hourglass_empty;
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(LeaveService.formatRange(item), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(statusIcon, size: 14, color: statusColor),
                                          const SizedBox(width: 4),
                                          Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                                        ],
                                      ),
                                    )
                                  ],
                                ),
                                const Divider(),
                                _buildLeaveDetail("Reason", item['reason'] as String),
                                _buildLeaveDetail("Sent to", "${item['teacher_name']} (${item['sent_to']})"),
                                if (remark != null && remark.isNotEmpty) _buildLeaveDetail("Remark", remark),
                                if (item['attachment_path'] != null)
                                  LeaveAttachmentButton(path: item['attachment_path'] as String),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              )
            ],
          ),
        );
      },
    );
  }

  // Camera or gallery on phones; file picker on web
  Future<Uint8List?> _pickLeavePhoto(BuildContext ctx) async {
    ImageSource? source = ImageSource.gallery;
    if (!kIsWeb) {
      source = await showModalBottomSheet<ImageSource>(
        context: ctx,
        builder: (sheet) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text("Take a photo"),
                onTap: () => Navigator.pop(sheet, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text("Choose from gallery"),
                onTap: () => Navigator.pop(sheet, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null) return null;
    }
    try {
      final file = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1600);
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      if (bytes.length > LeaveService.maxAttachmentBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("This photo is too large (over 5 MB). Choose a smaller one.")),
          );
        }
        return null;
      }
      return bytes;
    } catch (e) {
      debugPrint('Pick photo error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open the camera or gallery.")),
        );
      }
      return null;
    }
  }

  Widget _buildLeaveDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _showAttendanceLogSheet(BuildContext context, String subjectName) {
    List<Map<String, String>> logs = attendanceLogs[selectedSubjectCode] ?? [];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("$subjectName Attendance", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kalgidharBlue)),
            const Divider(),
            Expanded(
              child: logs.isEmpty
                  ? const Center(child: Text("No lectures have been marked for this subject yet.", style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                itemCount: logs.length,
                itemBuilder: (ctx, i) => ListTile(
                  title: Text(logs[i]['date']!),
                  trailing: Text(logs[i]['status']!, style: TextStyle(fontWeight: FontWeight.bold, color: logs[i]['status'] == 'Present' ? Colors.green : Colors.red)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTestLogSheet(BuildContext context, String subjectName, List<Map<String, dynamic>> tests) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("$subjectName Scores", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
            const Divider(),
            Expanded(
              child: tests.isEmpty
                  ? const Center(child: Text("No Monday Test marks uploaded for this subject yet.", style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                itemCount: tests.length,
                itemBuilder: (ctx, i) => ListTile(
                  title: Text(tests[i]['test']),
                  trailing: tests[i]['absent'] == true
                      ? const Text("Absent", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))
                      : Text("${_fmtScore(tests[i]['score'])} / ${_fmtScore(tests[i]['max'] ?? 17)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _messagesSubtitle() {
    final inbox = _inbox;
    if (inbox == null || !inbox.loaded) return "Loading...";
    if (inbox.items.isEmpty) return "No messages yet";
    final unread = inbox.unreadCount;
    if (unread > 0) return "$unread unread  |  Latest: ${inbox.items.first.title}";
    return "All read  |  Latest: ${inbox.items.first.title}";
  }

  // Opens the inbox. Opening a message marks it read; you can reply inside.
  void _showMessageCenter(BuildContext context) {
    final inbox = _inbox;
    if (inbox == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InboxPage(controller: inbox, title: "Faculty & Admin Messages")),
    ).then((_) => inbox.refresh());
  }

  Widget _buildSectionTitle(String title) => Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));

  Widget _buildAttendanceCard(String title, String subtitle, double percentage, int attended, int total, bool isOverall) {
    Color color = isOverall ? kalgidharBlue : (percentage < 0.75 ? Colors.redAccent : Colors.green);
    return Card(
      elevation: 3, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Stack(alignment: Alignment.center, children: [
            SizedBox(height: 70, width: 70, child: CircularProgressIndicator(value: percentage, strokeWidth: 8, backgroundColor: Colors.grey[200], valueColor: AlwaysStoppedAnimation(color))),
            Text('${(percentage * 100).toInt()}%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          ]),
          const SizedBox(width: 20),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (!isOverall) Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text("$attended / $total Attended", style: const TextStyle(fontWeight: FontWeight.w500)),
          ]),
        ]),
      ),
    );
  }

  Widget _buildTestPerformanceCard(String name, double avg, double pct) {
    return Card(
      elevation: 3, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Stack(alignment: Alignment.center, children: [
            SizedBox(height: 70, width: 70, child: CircularProgressIndicator(value: pct, strokeWidth: 8, backgroundColor: Colors.grey[200], valueColor: const AlwaysStoppedAnimation(Colors.deepPurple))),
            Text(avg.toStringAsFixed(1), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
          ]),
          const SizedBox(width: 20),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Monday Test (Max 17)", style: TextStyle(fontWeight: FontWeight.bold)),
            Text(name, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ]),
      ),
    );
  }
}