import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'main.dart'; // LoginScreen (logout)
import 'app_session.dart';
import 'management_service.dart';
import 'password_dialog.dart';

const Color _mgmtGreen = Color(0xFF1B5E20);

// =====================================================================
// MANAGEMENT PORTAL
// A separate office that manages accounts:
//   * adds students, teachers, admins (with login ID + password)
//   * edits details, turns accounts off/on, resets passwords
//   * adds departments and classes, sets class in-charge
// =====================================================================
class ManagementDashboard extends StatefulWidget {
  const ManagementDashboard({super.key});

  @override
  State<ManagementDashboard> createState() => _ManagementDashboardState();
}

class _ManagementDashboardState extends State<ManagementDashboard> with SingleTickerProviderStateMixin {
  final AppUser? me = AppSession.currentUser;
  late final TabController _tabs = TabController(length: 4, vsync: this);

  List<ManagedUser> _students = [];
  List<ManagedUser> _teachers = [];
  List<ManagedUser> _staff = []; // admin + management
  Map<int, String> _departments = {};
  List<Map<String, dynamic>> _classes = [];
  bool _loading = true;
  String? _error;

  final TextEditingController _search = TextEditingController();
  int? _classFilter; // students tab
  int? _deptFilter; // teachers tab

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await ManagementService.loadUsers(['student', 'faculty', 'admin', 'management']);
      final departments = await ManagementService.loadDepartments();
      final classes = await ManagementService.loadClasses();
      if (!mounted) return;
      setState(() {
        _students = users.where((u) => u.role == 'student').toList();
        _teachers = users.where((u) => u.role == 'faculty').toList();
        _staff = users.where((u) => u.role == 'admin' || u.role == 'management').toList();
        _departments = departments;
        _classes = classes;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Management load error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load accounts. Check your internet connection.';
        });
      }
    }
  }

  void _logout() {
    AppSession.signOut();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen()),
      (Route<dynamic> route) => false,
    );
  }

  String _className(int? id) {
    if (id == null) return '-';
    final c = _classes.where((c) => c['id'] == id);
    return c.isEmpty ? '-' : c.first['name'] as String;
  }

  String _teacherName(String? id) {
    if (id == null) return 'not set';
    final t = _teachers.where((t) => t.id == id);
    return t.isEmpty ? 'not set' : t.first.fullName;
  }

  List<ManagedUser> _filtered(List<ManagedUser> list) {
    final q = _search.text.trim().toLowerCase();
    return list.where((u) {
      if (_tabs.index == 0 && _classFilter != null && u.classId != _classFilter) return false;
      if (_tabs.index == 1 && _deptFilter != null && u.departmentId != _deptFilter) return false;
      if (q.isEmpty) return true;
      return u.fullName.toLowerCase().contains(q) || u.loginId.toLowerCase().contains(q);
    }).toList();
  }

  // ------------------------------------------------------------------
  // ACTIONS
  // ------------------------------------------------------------------

  Future<void> _openEditor({required String role, ManagedUser? user}) async {
    if (role == 'student' && _classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Add a class first (Classes tab), then add students to it.")),
      );
      return;
    }
    final result = await showDialog<_EditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UserEditorDialog(
        role: role,
        user: user,
        departments: _departments,
        classes: _classes,
        myId: me?.id,
      ),
    );
    if (result == null || !mounted) return;
    await _load();
    if (!mounted) return;
    if (result.password != null) {
      await showCredentials(context, name: result.name, role: role, loginId: result.loginId, password: result.password!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Saved ${result.name}."), backgroundColor: Colors.green[700]),
      );
    }
  }

  Future<void> _addDepartment() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add Department"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: "Department name", hintText: "e.g. Civil Eng"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text("Add")),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await ManagementService.addDepartment(name);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Added department $name.")));
    } catch (e) {
      debugPrint('Add department error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ManagementService.friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openClassEditor({Map<String, dynamic>? cls}) async {
    if (_departments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Add a department first.")));
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ClassEditorDialog(cls: cls, departments: _departments, teachers: _teachers),
    );
    if (saved == true) await _load();
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tab = _tabs.index;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F4),
      appBar: AppBar(
        backgroundColor: _mgmtGreen,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Management Portal"),
            Text(me?.fullName ?? '', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(tooltip: "Refresh", onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            tooltip: "Change my password",
            onPressed: () => showChangePasswordDialog(context),
            icon: const Icon(Icons.lock_outline),
          ),
          IconButton(tooltip: "Logout", onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(icon: const Icon(Icons.school), text: "Students (${_students.length})"),
            Tab(icon: const Icon(Icons.person), text: "Teachers (${_teachers.length})"),
            Tab(icon: const Icon(Icons.admin_panel_settings), text: "Admins (${_staff.length})"),
            Tab(icon: const Icon(Icons.class_), text: "Classes (${_classes.length})"),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                      TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text("Try again")),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildUserTab(_students, 'student'),
                    _buildUserTab(_teachers, 'faculty'),
                    _buildUserTab(_staff, 'admin'),
                    _buildClassesTab(),
                  ],
                ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              backgroundColor: _mgmtGreen,
              foregroundColor: Colors.white,
              onPressed: () {
                switch (tab) {
                  case 0:
                    _openEditor(role: 'student');
                    break;
                  case 1:
                    _openEditor(role: 'faculty');
                    break;
                  case 2:
                    _openEditor(role: 'admin');
                    break;
                  default:
                    _openClassEditor();
                }
              },
              icon: const Icon(Icons.add),
              label: Text(const ["Add Student", "Add Teacher", "Add Admin", "Add Class"][tab]),
            ),
    );
  }

  Widget _buildUserTab(List<ManagedUser> all, String role) {
    final list = _filtered(all);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: "Search name or ID",
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              if (role == 'student' || role == 'faculty') ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade400),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: role == 'student'
                        ? DropdownButton<int?>(
                            value: _classFilter,
                            hint: const Text("All classes"),
                            items: [
                              const DropdownMenuItem<int?>(value: null, child: Text("All classes")),
                              ..._classes.map((c) => DropdownMenuItem<int?>(value: c['id'] as int, child: Text(c['name'] as String))),
                            ],
                            onChanged: (v) => setState(() => _classFilter = v),
                          )
                        : DropdownButton<int?>(
                            value: _deptFilter,
                            hint: const Text("All departments"),
                            items: [
                              const DropdownMenuItem<int?>(value: null, child: Text("All departments")),
                              ..._departments.entries.map((d) => DropdownMenuItem<int?>(value: d.key, child: Text(d.value))),
                            ],
                            onChanged: (v) => setState(() => _deptFilter = v),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: list.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: Text("No accounts found.", style: TextStyle(color: Colors.grey))),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final u = list[i];
                      final where = u.role == 'student'
                          ? _className(u.classId)
                          : (_departments[u.departmentId] ?? (u.role == 'management' ? 'Management' : 'Admin office'));
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        color: u.isActive ? Colors.white : Colors.grey.shade200,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _mgmtGreen.withOpacity(0.1),
                            child: Text(u.fullName.isEmpty ? '?' : u.fullName[0], style: const TextStyle(color: _mgmtGreen)),
                          ),
                          title: Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text("ID: ${u.loginId}  |  $where${u.designation != null ? '  |  ${u.designation}' : ''}"),
                          trailing: u.isActive
                              ? const Icon(Icons.edit, size: 18, color: Colors.grey)
                              : Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                                  child: Text("Off", style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                          onTap: () => _openEditor(role: u.role, user: u),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildClassesTab() {
    final byDept = <String, List<Map<String, dynamic>>>{};
    for (final c in _classes) {
      final dept = _departments[c['department_id']] ?? 'Other';
      byDept.putIfAbsent(dept, () => []).add(c);
    }
    final deptNames = byDept.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        children: [
          Row(
            children: [
              Expanded(
                child: Text("${_departments.length} departments, ${_classes.length} classes",
                    style: const TextStyle(color: Colors.grey)),
              ),
              OutlinedButton.icon(onPressed: _addDepartment, icon: const Icon(Icons.add), label: const Text("Department")),
            ],
          ),
          const SizedBox(height: 8),
          if (_classes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: Text("No classes yet. Tap Add Class.", style: TextStyle(color: Colors.grey))),
            ),
          for (final dept in deptNames) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(dept, style: const TextStyle(fontWeight: FontWeight.bold, color: _mgmtGreen, fontSize: 15)),
            ),
            ...byDept[dept]!.map((c) {
              final count = _students.where((s) => s.classId == c['id']).length;
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: const Icon(Icons.class_, color: _mgmtGreen),
                  title: Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text("In-charge: ${_teacherName(c['class_teacher_id'] as String?)}  |  $count students"),
                  trailing: const Icon(Icons.edit, size: 18, color: Colors.grey),
                  onTap: () => _openClassEditor(cls: c),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// =====================================================================
// CREDENTIALS CARD: shown after creating an account or resetting a
// password, so the office can give the details to the person.
// =====================================================================
Future<void> showCredentials(
  BuildContext context, {
  required String name,
  required String role,
  required String loginId,
  required String password,
}) {
  final roleName = const {'student': 'Student', 'faculty': 'Faculty', 'admin': 'Admin', 'management': 'Management'}[role] ?? role;
  final text = "AttendEase login\n"
      "Name: $name\n"
      "Log in as: $roleName\n"
      "User Name: $loginId\n"
      "Password: $password\n"
      "You will be asked to choose your own password after logging in.";

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: const Row(
        children: [
          Icon(Icons.verified_user, color: _mgmtGreen),
          SizedBox(width: 8),
          Text("Login Details"),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Give these details to $name:", style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
            child: SelectableText(
              "Log in as: $roleName\nUser Name: $loginId\nPassword: $password",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.5),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "This password is shown only now. They will be asked to change it after logging in.",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Copied. You can paste it in WhatsApp or SMS.")));
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text("Copy"),
        ),
        ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text("Done")),
      ],
    ),
  );
}

// =====================================================================
// ADD / EDIT AN ACCOUNT
// =====================================================================
class _EditorResult {
  final String name;
  final String loginId;
  final String? password; // set when a new account was created
  const _EditorResult({required this.name, required this.loginId, this.password});
}

class _UserEditorDialog extends StatefulWidget {
  final String role;
  final ManagedUser? user; // null = add new
  final Map<int, String> departments;
  final List<Map<String, dynamic>> classes;
  final String? myId;

  const _UserEditorDialog({
    required this.role,
    required this.user,
    required this.departments,
    required this.classes,
    required this.myId,
  });

  @override
  State<_UserEditorDialog> createState() => _UserEditorDialogState();
}

class _UserEditorDialogState extends State<_UserEditorDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.user?.fullName ?? '');
  late final TextEditingController _loginId = TextEditingController(text: widget.user?.loginId ?? '');
  late final TextEditingController _designation = TextEditingController(text: widget.user?.designation ?? '');
  late final TextEditingController _password = TextEditingController(text: ManagementService.generatePassword());
  late String _role = widget.user?.role ?? widget.role;
  late int? _classId = widget.user?.classId;
  late int? _deptId = widget.user?.departmentId;
  late bool _active = widget.user?.isActive ?? true;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.user == null;
  bool get _isStudent => _role == 'student';
  bool get _isFaculty => _role == 'faculty';

  @override
  void dispose() {
    _name.dispose();
    _loginId.dispose();
    _designation.dispose();
    _password.dispose();
    super.dispose();
  }

  String get _title {
    final who = const {'student': 'Student', 'faculty': 'Teacher', 'admin': 'Admin', 'management': 'Management'}[_role] ?? 'Account';
    return _isNew ? "Add $who" : "Edit $who";
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _loginId.text.trim().isEmpty) {
      setState(() => _error = _isStudent ? "Enter the name and roll number." : "Enter the name and staff ID.");
      return;
    }
    if (_isStudent && _classId == null) {
      setState(() => _error = "Choose the student's class.");
      return;
    }
    if (_isFaculty && _deptId == null) {
      setState(() => _error = "Choose the teacher's department.");
      return;
    }
    if (_isNew && _password.text.length < 6) {
      setState(() => _error = "The password must have at least 6 characters.");
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String? error;
      if (_isNew) {
        error = await ManagementService.createUser(
          role: _role,
          loginId: _loginId.text,
          fullName: _name.text,
          password: _password.text,
          departmentId: _isStudent ? null : _deptId,
          classId: _isStudent ? _classId : null,
          designation: _designation.text.trim().isEmpty ? null : _designation.text.trim(),
        );
      } else {
        error = await ManagementService.updateUser(
          userId: widget.user!.id,
          loginId: _loginId.text,
          fullName: _name.text,
          departmentId: _isStudent ? null : _deptId,
          classId: _isStudent ? _classId : null,
          designation: _designation.text.trim().isEmpty ? null : _designation.text.trim(),
          isActive: _active,
        );
      }
      if (!mounted) return;
      if (error != null) {
        setState(() {
          _busy = false;
          _error = error;
        });
        return;
      }
      Navigator.pop(
        context,
        _EditorResult(
          name: _name.text.trim(),
          loginId: _loginId.text.trim().toUpperCase(),
          password: _isNew ? _password.text : null,
        ),
      );
    } catch (e) {
      debugPrint('Save account error: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = ManagementService.friendlyError(e);
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    final user = widget.user;
    if (user == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reset Password?"),
        content: Text("${user.fullName} will get a new password and will be logged out on all phones."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Reset")),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final newPassword = ManagementService.generatePassword();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final error = await ManagementService.resetPassword(userId: user.id, newPassword: newPassword);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error;
      });
      if (error == null) {
        await showCredentials(context, name: user.fullName, role: user.role, loginId: user.loginId, password: newPassword);
      }
    } catch (e) {
      debugPrint('Reset password error: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = ManagementService.friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedClasses = [...widget.classes]..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: Text(_title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isNew && (widget.role == 'admin' || widget.role == 'management')) ...[
                DropdownButtonFormField<String>(
                  value: _role,
                  decoration: const InputDecoration(labelText: "Account type", border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text("Admin")),
                    DropdownMenuItem(value: 'management', child: Text("Management")),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _role = v ?? 'admin'),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _name,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: "Full name", border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _loginId,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: _isStudent ? "Roll number (User Name)" : "Staff ID (User Name)",
                  hintText: _isStudent ? "e.g. 2506" : "e.g. FAC-010",
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              if (_isStudent)
                DropdownButtonFormField<int>(
                  value: _classId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: "Class", border: OutlineInputBorder(), isDense: true),
                  items: sortedClasses
                      .map((c) => DropdownMenuItem(
                            value: c['id'] as int,
                            child: Text("${c['name']}  (${widget.departments[c['department_id']] ?? ''})"),
                          ))
                      .toList(),
                  onChanged: _busy ? null : (v) => setState(() => _classId = v),
                )
              else
                DropdownButtonFormField<int?>(
                  value: _deptId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _isFaculty ? "Department" : "Department (optional)",
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    if (!_isFaculty) const DropdownMenuItem<int?>(value: null, child: Text("None")),
                    ...widget.departments.entries.map((d) => DropdownMenuItem<int?>(value: d.key, child: Text(d.value))),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _deptId = v),
                ),
              if (!_isStudent) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _designation,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: "Designation",
                    hintText: _isFaculty ? "e.g. HOD, Assistant Prof" : "e.g. Registrar",
                    helperText: _isFaculty ? "Write HOD to give department performance access" : null,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              if (_isNew) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: "Starting password",
                    helperText: "They will be asked to change it after logging in",
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      tooltip: "New random password",
                      icon: const Icon(Icons.casino_outlined),
                      onPressed: _busy ? null : () => setState(() => _password.text = ManagementService.generatePassword()),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Account is on"),
                  subtitle: Text(_active ? "This person can log in" : "This person cannot log in"),
                  value: _active,
                  activeColor: _mgmtGreen,
                  onChanged: (_busy || widget.user?.id == widget.myId) ? null : (v) => setState(() => _active = v),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _resetPassword,
                  icon: const Icon(Icons.key),
                  label: const Text("Reset Password"),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _mgmtGreen, foregroundColor: Colors.white),
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_isNew ? "Create Account" : "Save"),
        ),
      ],
    );
  }
}

// =====================================================================
// ADD / EDIT A CLASS
// =====================================================================
class _ClassEditorDialog extends StatefulWidget {
  final Map<String, dynamic>? cls; // null = add new
  final Map<int, String> departments;
  final List<ManagedUser> teachers;

  const _ClassEditorDialog({required this.cls, required this.departments, required this.teachers});

  @override
  State<_ClassEditorDialog> createState() => _ClassEditorDialogState();
}

class _ClassEditorDialogState extends State<_ClassEditorDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.cls?['name'] as String? ?? '');
  late int? _deptId = widget.cls?['department_id'] as int? ?? widget.departments.keys.first;
  late String? _teacherId = widget.cls?['class_teacher_id'] as String?;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.cls == null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isNew && _name.text.trim().isEmpty) {
      setState(() => _error = "Enter the class name.");
      return;
    }
    if (_isNew && _deptId == null) {
      setState(() => _error = "Choose the department.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isNew) {
        await ManagementService.addClass(name: _name.text, departmentId: _deptId!, classTeacherId: _teacherId);
      } else {
        await ManagementService.setClassTeacher(widget.cls!['id'] as int, _teacherId);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Save class error: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = ManagementService.friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Teachers of the chosen department first
    final teachers = widget.teachers.where((t) => t.isActive).toList()
      ..sort((a, b) {
        final aMine = a.departmentId == _deptId ? 0 : 1;
        final bMine = b.departmentId == _deptId ? 0 : 1;
        return aMine != bMine ? aMine - bMine : a.fullName.compareTo(b.fullName);
      });

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: Text(_isNew ? "Add Class" : "Class ${widget.cls!['name']}"),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isNew) ...[
              TextField(
                controller: _name,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: "Class name", hintText: "e.g. CS-C", border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _deptId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: "Department", border: OutlineInputBorder(), isDense: true),
                items: widget.departments.entries.map((d) => DropdownMenuItem(value: d.key, child: Text(d.value))).toList(),
                onChanged: _busy ? null : (v) => setState(() => _deptId = v),
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<String?>(
              value: teachers.any((t) => t.id == _teacherId) ? _teacherId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: "Class in-charge (teacher)", border: OutlineInputBorder(), isDense: true),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text("Not set")),
                ...teachers.map((t) => DropdownMenuItem<String?>(
                      value: t.id,
                      child: Text("${t.fullName} (${t.loginId})${widget.departments[t.departmentId] != null ? ' - ${widget.departments[t.departmentId]}' : ''}",
                          overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: _busy ? null : (v) => setState(() => _teacherId = v),
            ),
            const SizedBox(height: 6),
            const Text("The class in-charge receives students' leave requests.", style: TextStyle(fontSize: 12, color: Colors.grey)),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _mgmtGreen, foregroundColor: Colors.white),
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_isNew ? "Add Class" : "Save"),
        ),
      ],
    );
  }
}
