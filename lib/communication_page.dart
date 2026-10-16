import 'package:flutter/material.dart';
import 'app_session.dart';
import 'academic_service.dart';
import 'message_service.dart';
import 'message_thread_page.dart';

// =====================================================================
// MESSAGES PAGE (faculty and admin)
//   Inbox   - messages sent to me
//   Compose - send a new message
//   Sent    - messages I have sent, with who received them
//
// Faculty can message students of the classes they teach, or the admin
// office. Admin can message any department, class, student or faculty.
// =====================================================================
class CommunicationPage extends StatefulWidget {
  final bool embedded; // true = shown inside the admin dashboard (no app bar)
  final int initialTab; // 0 = Inbox, 1 = Compose, 2 = Sent

  const CommunicationPage({super.key, this.embedded = false, this.initialTab = 0});

  @override
  State<CommunicationPage> createState() => _CommunicationPageState();
}

class _CommunicationPageState extends State<CommunicationPage> with SingleTickerProviderStateMixin {
  final Color kalgidharBlue = const Color(0xFF002046);
  final AppUser? me = AppSession.currentUser;
  late final TabController _tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2).toInt());

  InboxController? _inbox;
  SentController? _sent;

  bool get _isAdmin => me?.role == 'admin';
  Color get _accent => _isAdmin ? Colors.indigo : kalgidharBlue;

  @override
  void initState() {
    super.initState();
    final user = me;
    if (user == null) return;
    _inbox = InboxController(userId: user.id)..start();
    _sent = SentController(userId: user.id)..start();
    _inbox!.addListener(_rebuild);
    _sent!.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _inbox?.removeListener(_rebuild);
    _sent?.removeListener(_rebuild);
    _inbox?.dispose();
    _sent?.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onSent() {
    _sent?.refresh();
    _tabs.animateTo(2); // show the Sent tab after sending
  }

  @override
  Widget build(BuildContext context) {
    final unread = _inbox?.unreadCount ?? 0;
    final newReplies = _sent?.newReplies ?? 0;

    final tabBar = TabBar(
      controller: _tabs,
      indicatorColor: widget.embedded ? _accent : Colors.white,
      labelColor: widget.embedded ? _accent : Colors.white,
      unselectedLabelColor: widget.embedded ? Colors.grey : Colors.white60,
      tabs: [
        Tab(
          icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.inbox)),
          text: unread == 0 ? "Inbox" : "Inbox ($unread unread)",
        ),
        const Tab(icon: Icon(Icons.edit), text: "Compose"),
        Tab(
          icon: Badge(isLabelVisible: newReplies > 0, label: Text('$newReplies'), child: const Icon(Icons.send)),
          text: newReplies == 0 ? "Sent" : "Sent ($newReplies new)",
        ),
      ],
    );

    final Widget views = (_inbox == null || _sent == null)
        ? const Center(child: Text("Please log in again."))
        : TabBarView(
            controller: _tabs,
            children: [
              InboxList(
                controller: _inbox!,
                emptyText: _isAdmin ? "No messages from faculty yet." : "No messages from the admin office yet.",
              ),
              _isAdmin ? AdminComposeForm(onSent: _onSent) : FacultyComposeForm(onSent: _onSent),
              SentList(controller: _sent!),
            ],
          );

    if (widget.embedded) {
      return Column(
        children: [
          Material(color: Colors.white, child: tabBar),
          Expanded(child: views),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        title: const Text("Messages"),
        bottom: tabBar,
      ),
      body: views,
    );
  }
}

// =====================================================================
// SENT LIST: each message with Delivered / Read / Replies
// =====================================================================
class SentList extends StatelessWidget {
  final SentController controller;
  const SentList({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.loaded) return const Center(child: CircularProgressIndicator());
        final items = controller.items;
        return RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            children: [
              if (controller.error != null)
                Text(controller.error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              if (items.isEmpty && controller.error == null)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: Text("You haven't sent any messages yet.", style: TextStyle(color: Colors.grey))),
                ),
              ...items.map((item) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: item.newReplies > 0 ? Colors.green.shade300 : Colors.grey.shade200),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("To: ${item.toLabel}  |  ${MessageService.timeAgo(item.sentAt)}",
                              style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.done, size: 14, color: Colors.grey),
                              Text(" ${item.delivered}  ", style: const TextStyle(fontSize: 12)),
                              const Icon(Icons.done_all, size: 14, color: Colors.blue),
                              Text(" ${item.readCount} read  ", style: const TextStyle(fontSize: 12, color: Colors.blue)),
                              const Icon(Icons.chat_bubble_outline, size: 13, color: Colors.grey),
                              Text(" ${item.conversations}", style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                      trailing: item.newReplies > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                              child: Text("${item.newReplies} new",
                                  style: TextStyle(color: Colors.green.shade800, fontSize: 11, fontWeight: FontWeight.bold)),
                            )
                          : const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => SentMessagePage(item: item)),
                      ).then((_) => controller.refresh()),
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }
}

// =====================================================================
// FACULTY: COMPOSE
//   To students of a class you teach (whole class or one student),
//   or to the admin office.
// =====================================================================
class FacultyComposeForm extends StatefulWidget {
  final VoidCallback? onSent;
  const FacultyComposeForm({super.key, this.onSent});

  @override
  State<FacultyComposeForm> createState() => _FacultyComposeFormState();
}

class _FacultyComposeFormState extends State<FacultyComposeForm> with AutomaticKeepAliveClientMixin {
  final Color kalgidharBlue = const Color(0xFF002046);
  final AppUser? me = AppSession.currentUser;

  static const String _toStudents = 'Students';
  static const String _toAdmin = 'Admin Office';

  // Classes this teacher teaches: classId -> class name
  Map<int, String> _myClasses = {};
  bool _loading = true;
  String? _loadError;

  String _sendTo = _toStudents;
  int? _classId;
  bool _wholeClass = true;
  List<ClassStudent> _students = [];
  bool _loadingStudents = false;
  ClassStudent? _student;
  bool _isHigh = false;
  bool _sending = false;
  String? _formError;
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _bodyCtrl = TextEditingController();

  @override
  bool get wantKeepAlive => true; // keep typed text when switching tabs

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    final teacher = me;
    if (teacher == null) return;
    try {
      final subjects = await AcademicService.loadFacultySubjects(teacher.id);
      if (!mounted) return;
      final classes = <int, String>{};
      for (final s in subjects) {
        classes[s.classId] = s.className;
      }
      setState(() {
        _myClasses = classes;
        _classId = classes.isEmpty ? null : classes.keys.first;
        if (classes.isEmpty) _sendTo = _toAdmin;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Compose load error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Could not load your classes. Check your internet connection.';
        });
      }
    }
  }

  Future<void> _loadStudents() async {
    final classId = _classId;
    if (classId == null) return;
    setState(() {
      _loadingStudents = true;
      _students = [];
      _student = null;
    });
    try {
      final list = await AcademicService.loadStudents(classId);
      if (mounted) setState(() => _students = list);
    } catch (e) {
      debugPrint('Load students error: $e');
    } finally {
      if (mounted) setState(() => _loadingStudents = false);
    }
  }

  String _targetLabel() {
    if (_sendTo == _toAdmin) return 'Admin Office';
    final className = _myClasses[_classId] ?? '';
    if (_wholeClass) return 'All students of $className';
    final st = _student;
    return st == null ? className : '${st.name} (${st.roll}), $className';
  }

  Future<void> _send() async {
    final teacher = me;
    if (teacher == null) return;
    if (_titleCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      setState(() => _formError = "Write a title and a message.");
      return;
    }
    if (_sendTo == _toStudents) {
      if (_classId == null) {
        setState(() => _formError = "Choose a class.");
        return;
      }
      if (!_wholeClass && _student == null) {
        setState(() => _formError = "Choose a student.");
        return;
      }
    }

    final label = _targetLabel();
    int delivered = 0;
    setState(() {
      _sending = true;
      _formError = null;
    });
    try {
      if (_sendTo == _toAdmin) {
        delivered = await MessageService.send(
          sender: teacher,
          audience: 'admin',
          title: _titleCtrl.text,
          body: _bodyCtrl.text,
          priority: _isHigh ? 'High' : 'Normal',
          targetLabel: label,
        );
      } else {
        delivered = await MessageService.send(
          sender: teacher,
          audience: 'students',
          title: _titleCtrl.text,
          body: _bodyCtrl.text,
          priority: _isHigh ? 'High' : 'Normal',
          classId: _wholeClass ? _classId : null,
          studentId: _wholeClass ? null : _student!.id,
          targetLabel: label,
        );
      }
      if (!mounted) return;
      _titleCtrl.clear();
      _bodyCtrl.clear();
      setState(() {
        _sending = false;
        _isHigh = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(delivered == 0
            ? "Saved, but no one matched \"$label\" (for example, the class has no students yet)."
            : "Delivered to $delivered ${delivered == 1 ? 'person' : 'people'}: $label."),
        backgroundColor: delivered == 0 ? Colors.orange[800] : Colors.green[700],
      ));
      widget.onSent?.call();
    } catch (e) {
      debugPrint('Send message error: $e');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _formError = MessageService.friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(child: Text(_loadError!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label("Send to"),
          DropdownButtonFormField<String>(
            value: _sendTo,
            isExpanded: true,
            decoration: _deco(),
            items: [
              if (_myClasses.isNotEmpty) const DropdownMenuItem(value: _toStudents, child: Text("Students")),
              const DropdownMenuItem(value: _toAdmin, child: Text("Admin Office")),
            ],
            onChanged: _sending ? null : (val) => setState(() => _sendTo = val ?? _toAdmin),
          ),
          if (_myClasses.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text("You have no classes assigned yet, so you can only message the admin office.",
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          if (_sendTo == _toStudents) ...[
            const SizedBox(height: 15),
            _label("Class"),
            DropdownButtonFormField<int>(
              value: _classId,
              isExpanded: true,
              decoration: _deco(),
              items: _myClasses.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: _sending
                  ? null
                  : (val) {
                      setState(() => _classId = val);
                      if (!_wholeClass) _loadStudents();
                    },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Whole class", style: TextStyle(fontSize: 14)),
                    value: true,
                    groupValue: _wholeClass,
                    onChanged: _sending ? null : (val) => setState(() => _wholeClass = true),
                  ),
                ),
                Expanded(
                  child: RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("One student", style: TextStyle(fontSize: 14)),
                    value: false,
                    groupValue: _wholeClass,
                    onChanged: _sending
                        ? null
                        : (val) {
                            setState(() => _wholeClass = false);
                            _loadStudents();
                          },
                  ),
                ),
              ],
            ),
            if (!_wholeClass)
              _loadingStudents
                  ? const LinearProgressIndicator()
                  : DropdownButtonFormField<ClassStudent>(
                      value: _student,
                      isExpanded: true,
                      decoration: _deco(hint: "Choose a student"),
                      items: _students
                          .map((st) => DropdownMenuItem(value: st, child: Text("${st.name} (${st.roll})", overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: _sending ? null : (val) => setState(() => _student = val),
                    ),
          ],
          const SizedBox(height: 15),
          _label("Title"),
          TextField(
            controller: _titleCtrl,
            enabled: !_sending,
            maxLength: 80,
            decoration: _deco(hint: _sendTo == _toAdmin ? "e.g. Projector not working in Room 101" : "e.g. Monday Test syllabus"),
          ),
          _label("Message"),
          TextField(
            controller: _bodyCtrl,
            enabled: !_sending,
            maxLines: 5,
            maxLength: 1000,
            decoration: _deco(hint: "Type your message..."),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Mark as important"),
            value: _isHigh,
            activeColor: Colors.red,
            onChanged: _sending ? null : (val) => setState(() => _isHigh = val),
          ),
          Text("Will be sent to: ${_targetLabel()}", style: TextStyle(color: kalgidharBlue, fontWeight: FontWeight.w600)),
          if (_formError != null) ...[
            const SizedBox(height: 8),
            Text(_formError!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: const Text("SEND"),
              style: ElevatedButton.styleFrom(backgroundColor: kalgidharBlue, foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) =>
      Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)));

  InputDecoration _deco({String? hint}) => InputDecoration(
        border: const OutlineInputBorder(),
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        isDense: true,
      );
}

// =====================================================================
// ADMIN: COMPOSE (broadcast)
//   Department -> Faculty or Students -> one person, a class, or everyone
// =====================================================================
class AdminComposeForm extends StatefulWidget {
  final VoidCallback? onSent;
  const AdminComposeForm({super.key, this.onSent});

  @override
  State<AdminComposeForm> createState() => _AdminComposeFormState();
}

class _AdminComposeFormState extends State<AdminComposeForm> with AutomaticKeepAliveClientMixin {
  static const String _all = '__all__';

  // Loaded from Supabase
  List<Map<String, dynamic>> _departments = []; // id, name
  List<Map<String, dynamic>> _classes = []; // id, name, department_id
  List<Map<String, dynamic>> _faculty = []; // id, full_name, department_id
  List<Map<String, dynamic>> _students = []; // id, full_name, login_id, class_id
  bool _loading = true;
  String? _loadError;

  String selectedDept = _all; // department id, or _all
  String? selectedRole; // 'Faculty' or 'Students'
  String selectedFaculty = _all;
  String selectedClass = _all;
  String selectedStudent = _all;
  bool _isHigh = false;
  bool _sending = false;
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _messageCtrl = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final depts = await supabase.from('departments').select('id, name').order('name', ascending: true);
      final classes = await supabase.from('classes').select('id, name, department_id').order('name', ascending: true);
      final faculty = await supabase
          .from('app_users')
          .select('id, full_name, department_id')
          .eq('role', 'faculty')
          .order('full_name', ascending: true);
      final students = await supabase
          .from('app_users')
          .select('id, full_name, login_id, class_id')
          .eq('role', 'student')
          .order('login_id', ascending: true);
      if (!mounted) return;
      setState(() {
        _departments = depts;
        _classes = classes;
        _faculty = faculty;
        _students = students;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Broadcast load error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Could not load departments and people. Check your internet connection.';
        });
      }
    }
  }

  int? get _deptId => selectedDept == _all ? null : int.parse(selectedDept);
  int? get _classId => selectedClass == _all ? null : int.parse(selectedClass);

  List<Map<String, dynamic>> get _availableClasses =>
      _deptId == null ? _classes : _classes.where((c) => c['department_id'] == _deptId).toList();
  List<Map<String, dynamic>> get _availableFaculty =>
      _deptId == null ? _faculty : _faculty.where((f) => f['department_id'] == _deptId).toList();
  List<Map<String, dynamic>> get _availableStudents =>
      _classId == null ? [] : _students.where((s) => s['class_id'] == _classId).toList();

  String _nameOf(List<Map<String, dynamic>> list, String id, String field) =>
      (list.firstWhere((x) => x['id'].toString() == id, orElse: () => {field: '?'})[field]).toString();

  // Plain-language summary of who will receive the message
  String _audienceSummary() {
    final deptName = _deptId == null ? null : _nameOf(_departments, selectedDept, 'name');
    if (selectedRole == 'Faculty') {
      if (selectedFaculty != _all) return _nameOf(_faculty, selectedFaculty, 'full_name');
      return deptName == null ? 'All faculty' : 'All faculty of $deptName';
    }
    if (selectedRole == 'Students') {
      if (selectedStudent != _all) {
        final st = _students.firstWhere((x) => x['id'] == selectedStudent, orElse: () => {'full_name': '?', 'login_id': ''});
        return "${st['full_name']} (${st['login_id']}), ${_nameOf(_classes, selectedClass, 'name')}";
      }
      if (_classId != null) return 'All students of ${_nameOf(_classes, selectedClass, 'name')}';
      return deptName == null ? 'All students' : 'All students of $deptName';
    }
    return '';
  }

  Future<void> _send() async {
    final admin = AppSession.currentUser;
    if (admin == null) return;
    if (selectedRole == null) {
      _snack('Choose who should receive the message.', Colors.orange[800]!);
      return;
    }
    if (_titleCtrl.text.trim().isEmpty || _messageCtrl.text.trim().isEmpty) {
      _snack('Write a title and a message.', Colors.orange[800]!);
      return;
    }

    final summary = _audienceSummary();
    int delivered = 0;
    setState(() => _sending = true);
    try {
      if (selectedRole == 'Faculty') {
        delivered = await MessageService.send(
          sender: admin,
          audience: 'faculty',
          title: _titleCtrl.text,
          body: _messageCtrl.text,
          priority: _isHigh ? 'High' : 'Normal',
          facultyId: selectedFaculty == _all ? null : selectedFaculty,
          departmentId: selectedFaculty == _all ? _deptId : null,
          targetLabel: summary,
        );
      } else {
        final toStudent = selectedStudent != _all;
        delivered = await MessageService.send(
          sender: admin,
          audience: 'students',
          title: _titleCtrl.text,
          body: _messageCtrl.text,
          priority: _isHigh ? 'High' : 'Normal',
          studentId: toStudent ? selectedStudent : null,
          classId: toStudent ? null : _classId,
          departmentId: (toStudent || _classId != null) ? null : _deptId,
          targetLabel: summary,
        );
      }
      if (!mounted) return;
      _titleCtrl.clear();
      _messageCtrl.clear();
      setState(() {
        _sending = false;
        _isHigh = false;
      });
      _snack(
        delivered == 0
            ? 'Saved, but no one matched "$summary" (for example, no students in that class yet).'
            : 'Delivered to $delivered ${delivered == 1 ? 'person' : 'people'}: $summary.',
        delivered == 0 ? Colors.orange[800]! : Colors.green[700]!,
      );
      widget.onSent?.call();
    } catch (e) {
      debugPrint('Broadcast send error: $e');
      if (!mounted) return;
      setState(() => _sending = false);
      _snack(MessageService.friendlyError(e), Colors.red);
    }
  }

  void _snack(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text("Try again")),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel("1. Select Department"),
          DropdownButtonFormField<String>(
            value: selectedDept,
            isExpanded: true,
            decoration: _inputDeco(),
            items: [
              const DropdownMenuItem(value: _all, child: Text("All Departments")),
              ..._departments.map((d) => DropdownMenuItem(value: d['id'].toString(), child: Text(d['name'] as String))),
            ],
            onChanged: (val) => setState(() {
              selectedDept = val ?? _all;
              selectedFaculty = _all;
              selectedClass = _all;
              selectedStudent = _all;
            }),
          ),
          const SizedBox(height: 15),
          _buildLabel("2. Select Recipient Group"),
          DropdownButtonFormField<String>(
            value: selectedRole,
            isExpanded: true,
            decoration: _inputDeco(),
            hint: const Text("Faculty or Students"),
            items: ['Faculty', 'Students'].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
            onChanged: (val) => setState(() {
              selectedRole = val;
              selectedFaculty = _all;
              selectedClass = _all;
              selectedStudent = _all;
            }),
          ),
          if (selectedRole == 'Faculty') ...[
            const SizedBox(height: 15),
            _buildLabel("3. Select Faculty"),
            DropdownButtonFormField<String>(
              value: selectedFaculty,
              isExpanded: true,
              decoration: _inputDeco(),
              items: [
                const DropdownMenuItem(value: _all, child: Text("All Faculty")),
                ..._availableFaculty.map((f) => DropdownMenuItem(value: f['id'] as String, child: Text(f['full_name'] as String))),
              ],
              onChanged: (val) => setState(() => selectedFaculty = val ?? _all),
            ),
          ],
          if (selectedRole == 'Students') ...[
            const SizedBox(height: 15),
            _buildLabel("3. Select Class"),
            DropdownButtonFormField<String>(
              value: selectedClass,
              isExpanded: true,
              decoration: _inputDeco(),
              items: [
                const DropdownMenuItem(value: _all, child: Text("All Classes")),
                ..._availableClasses.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name'] as String))),
              ],
              onChanged: (val) => setState(() {
                selectedClass = val ?? _all;
                selectedStudent = _all;
              }),
            ),
            if (selectedClass != _all) ...[
              const SizedBox(height: 15),
              _buildLabel("4. Select Student"),
              DropdownButtonFormField<String>(
                value: selectedStudent,
                isExpanded: true,
                decoration: _inputDeco(),
                items: [
                  const DropdownMenuItem(value: _all, child: Text("All Students")),
                  ..._availableStudents.map((st) =>
                      DropdownMenuItem(value: st['id'] as String, child: Text("${st['full_name']} (${st['login_id']})"))),
                ],
                onChanged: (val) => setState(() => selectedStudent = val ?? _all),
              ),
            ]
          ],
          if (selectedRole != null) ...[
            const SizedBox(height: 12),
            Text("Will be sent to: ${_audienceSummary()}", style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 25),
          const Text("Title:", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          TextField(
            controller: _titleCtrl,
            enabled: !_sending,
            maxLength: 80,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "e.g. Holiday Notice"),
          ),
          const Text("Message Content:", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          TextField(
            controller: _messageCtrl,
            enabled: !_sending,
            maxLines: 4,
            maxLength: 1000,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "e.g. College will be closed on Friday."),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Mark as important"),
            value: _isHigh,
            activeColor: Colors.red,
            onChanged: _sending ? null : (val) => setState(() => _isHigh = val),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: const Text("SEND"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) =>
      Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)));
  InputDecoration _inputDeco() => const InputDecoration(
      border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10), isDense: true);
}
