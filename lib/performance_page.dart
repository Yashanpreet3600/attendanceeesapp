import 'package:flutter/material.dart';
import 'performance_service.dart';
import 'excel_export.dart';

// Colors used for performance numbers
Color attendanceColor(double? pct) {
  if (pct == null) return Colors.grey;
  return pct < 75 ? Colors.red.shade700 : Colors.green.shade700;
}

Color marksColor(double? pct) {
  if (pct == null) return Colors.grey;
  if (pct < 35) return Colors.red.shade700;
  if (pct < 70) return Colors.orange.shade800;
  return Colors.green.shade700;
}

String pctLabel(double? pct) => pct == null ? '-' : '${pct.toStringAsFixed(pct >= 99.95 ? 0 : 1)}%';

// =====================================================================
// CLASS PERFORMANCE OVERVIEW
//   Admin: all departments (with a department filter)
//   HOD:   only their own department (lockDepartment = true)
// =====================================================================
class ClassPerformancePage extends StatefulWidget {
  final int? departmentId; // starting department (null = all)
  final bool lockDepartment; // HOD: can't change department
  final bool showAppBar; // false when shown inside the admin dashboard
  final String title;

  const ClassPerformancePage({
    super.key,
    this.departmentId,
    this.lockDepartment = false,
    this.showAppBar = true,
    this.title = 'Class Performance',
  });

  @override
  State<ClassPerformancePage> createState() => _ClassPerformancePageState();
}

class _ClassPerformancePageState extends State<ClassPerformancePage> {
  Map<int, String> _departments = {};
  int? _deptId;
  List<ClassSummary> _classes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _deptId = widget.departmentId;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!widget.lockDepartment && _departments.isEmpty) {
        _departments = await PerformanceService.loadDepartments();
      }
      final classes = await PerformanceService.loadClassSummaries(departmentId: _deptId);
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Class performance load error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load class performance. Check your internet connection, and make sure '
              'supabase_phase3.sql has been run in Supabase.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          if (!widget.lockDepartment)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.indigo.withOpacity(0.3)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: _deptId,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text("All Departments")),
                    ..._departments.entries.map((e) => DropdownMenuItem<int?>(value: e.key, child: Text(e.value))),
                  ],
                  onChanged: (val) {
                    setState(() => _deptId = val);
                    _load();
                  },
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                  TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text("Try again")),
                ],
              ),
            )
          else if (_classes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: Text("No classes found.", style: TextStyle(color: Colors.grey))),
            )
          else ...[
            _buildTotals(),
            const SizedBox(height: 12),
            ..._classes.map(_buildClassCard),
          ],
        ],
      ),
    );

    if (!widget.showAppBar) return body;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: body,
    );
  }

  // Totals across all classes shown
  Widget _buildTotals() {
    final students = _classes.fold<int>(0, (a, c) => a + c.students);
    final present = _classes.fold<int>(0, (a, c) => a + c.present);
    final marked = _classes.fold<int>(0, (a, c) => a + c.totalMarked);
    final marks = _classes.fold<double>(0, (a, c) => a + c.marksSum);
    final max = _classes.fold<double>(0, (a, c) => a + c.maxSum);
    final below = _classes.fold<int>(0, (a, c) => a + c.below75);
    final att = marked == 0 ? null : present * 100 / marked;
    final test = max == 0 ? null : marks * 100 / max;

    return Row(
      children: [
        _StatBox(label: "Students", value: "$students", color: Colors.indigo),
        const SizedBox(width: 8),
        _StatBox(label: "Attendance", value: pctLabel(att), color: attendanceColor(att)),
        const SizedBox(width: 8),
        _StatBox(label: "Test Avg", value: pctLabel(test), color: marksColor(test)),
        const SizedBox(width: 8),
        _StatBox(label: "Below 75%", value: "$below", color: below > 0 ? Colors.red.shade700 : Colors.green.shade700),
      ],
    );
  }

  Widget _buildClassCard(ClassSummary c) {
    final att = c.attendancePct;
    final test = c.testPct;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ClassPerformanceDetailPage(classId: c.classId, className: c.className)),
        ).then((_) => _load()),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(c.className, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                  ),
                  if (c.below75 > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                      child: Text("${c.below75} below 75%",
                          style: TextStyle(color: Colors.red.shade700, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              Text(
                "${c.departmentName}  |  In-charge: ${c.classTeacherName ?? 'not set'}  |  ${c.students} students",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              _MetricBar(label: "Attendance", pct: att, color: attendanceColor(att), note: "${c.lectures} lectures"),
              const SizedBox(height: 8),
              _MetricBar(label: "Monday Test", pct: test, color: marksColor(test), note: "${c.tests} tests"),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// ONE CLASS: students and subjects
// =====================================================================
class ClassPerformanceDetailPage extends StatefulWidget {
  final int classId;
  final String className;

  const ClassPerformanceDetailPage({super.key, required this.classId, required this.className});

  @override
  State<ClassPerformanceDetailPage> createState() => _ClassPerformanceDetailPageState();
}

class _ClassPerformanceDetailPageState extends State<ClassPerformanceDetailPage> {
  ClassDetail? _detail;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  String _sortBy = 'attendance'; // 'attendance', 'marks', 'roll'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await PerformanceService.loadClassDetail(widget.classId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        if (detail == null) _error = 'This class was not found.';
      });
    } catch (e) {
      debugPrint('Class detail load error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load this class. Check your internet connection.';
        });
      }
    }
  }

  Future<void> _export() async {
    final detail = _detail;
    if (detail == null || _exporting) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final result = await ExcelExport.classPerformanceReport(detail);
      if (!mounted) return;
      if (result.noData) {
        messenger.showSnackBar(const SnackBar(content: Text("There are no students in this class yet.")));
      } else if (result.saved) {
        messenger.showSnackBar(SnackBar(
          content: Text("Excel file saved to ${result.location}."),
          backgroundColor: Colors.green[700],
        ));
      }
    } catch (e) {
      debugPrint('Class report export error: $e');
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text("Could not create the Excel file. Try again."),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  List<StudentPerformance> _sortedStudents(List<StudentPerformance> list) {
    final sorted = [...list];
    // Students with no data go to the end
    double key(double? v) => v ?? 1000;
    switch (_sortBy) {
      case 'marks':
        sorted.sort((a, b) => key(a.testPct).compareTo(key(b.testPct)));
        break;
      case 'roll':
        sorted.sort((a, b) => a.roll.compareTo(b.roll));
        break;
      default:
        sorted.sort((a, b) => key(a.attendancePct).compareTo(key(b.attendancePct)));
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          title: Text("${widget.className} Performance"),
          actions: [
            IconButton(
              tooltip: "Download Excel report",
              onPressed: (_detail == null || _exporting) ? null : _export,
              icon: _exporting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: [Tab(text: "STUDENTS", icon: Icon(Icons.people)), Tab(text: "SUBJECTS", icon: Icon(Icons.menu_book))],
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
                : TabBarView(children: [_buildStudentsTab(_detail!), _buildSubjectsTab(_detail!)]),
      ),
    );
  }

  Widget _buildHeader(ClassDetail d) {
    final s = d.summary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("${s.departmentName}  |  In-charge: ${s.classTeacherName ?? 'not set'}",
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(
            children: [
              _StatBox(label: "Students", value: "${s.students}", color: Colors.indigo),
              const SizedBox(width: 8),
              _StatBox(label: "Attendance", value: pctLabel(s.attendancePct), color: attendanceColor(s.attendancePct)),
              const SizedBox(width: 8),
              _StatBox(label: "Test Avg", value: pctLabel(s.testPct), color: marksColor(s.testPct)),
              const SizedBox(width: 8),
              _StatBox(
                  label: "Below 75%",
                  value: "${s.below75}",
                  color: s.below75 > 0 ? Colors.red.shade700 : Colors.green.shade700),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStudentsTab(ClassDetail d) {
    final students = _sortedStudents(d.students);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildHeader(d),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text("Sort by: ", style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: _sortBy,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'attendance', child: Text("Lowest attendance first")),
                    DropdownMenuItem(value: 'marks', child: Text("Lowest marks first")),
                    DropdownMenuItem(value: 'roll', child: Text("Roll number")),
                  ],
                  onChanged: (val) => setState(() => _sortBy = val ?? 'attendance'),
                ),
              ],
            ),
          ),
          if (students.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: Text("No students in this class yet.", style: TextStyle(color: Colors.grey))),
            ),
          ...students.map((st) => Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: (st.lowAttendance || st.lowMarks) ? Colors.red.shade200 : Colors.grey.shade200),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.shade50,
                    child: Text(st.name.isEmpty ? '?' : st.name[0], style: const TextStyle(color: Colors.indigo)),
                  ),
                  title: Text(st.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Roll No: ${st.roll}"
                      "${st.lowAttendance ? '  |  Low attendance' : ''}"
                      "${st.lowMarks ? '  |  Low marks' : ''}"),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("Att ${pctLabel(st.attendancePct)}",
                          style: TextStyle(color: attendanceColor(st.attendancePct), fontWeight: FontWeight.bold, fontSize: 12)),
                      Text("Test ${pctLabel(st.testPct)}",
                          style: TextStyle(color: marksColor(st.testPct), fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                  onTap: () => _showStudentSheet(d, st),
                ),
              )),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showStudentSheet(ClassDetail d, StudentPerformance st) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(st.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo)),
            Text("Roll No: ${st.roll}  |  ${d.summary.className}", style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 10),
            Row(
              children: [
                _StatBox(label: "Attendance", value: pctLabel(st.attendancePct), color: attendanceColor(st.attendancePct)),
                const SizedBox(width: 8),
                _StatBox(label: "Test Avg", value: pctLabel(st.testPct), color: marksColor(st.testPct)),
                const SizedBox(width: 8),
                _StatBox(label: "Tests Absent", value: "${st.testsAbsent}", color: st.testsAbsent > 0 ? Colors.orange.shade800 : Colors.green.shade700),
              ],
            ),
            const Divider(height: 24),
            const Text("Subject-wise", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            Expanded(
              child: d.subjects.isEmpty
                  ? const Center(child: Text("No subjects set up for this class yet.", style: TextStyle(color: Colors.grey)))
                  : ListView(
                      children: d.subjects.map((sub) {
                        final stat = st.bySubject[sub.subjectId];
                        final att = stat?.attendancePct;
                        final test = stat?.testPct;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text("${sub.name} (${sub.code})", style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(stat == null
                              ? "No attendance or marks yet"
                              : "Present ${stat.present}/${stat.total}  |  Tests taken ${stat.testsTaken}"
                                  "${stat.testsAbsent > 0 ? ', absent ${stat.testsAbsent}' : ''}"),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text("Att ${pctLabel(att)}",
                                  style: TextStyle(color: attendanceColor(att), fontWeight: FontWeight.bold, fontSize: 12)),
                              Text("Test ${pctLabel(test)}",
                                  style: TextStyle(color: marksColor(test), fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectsTab(ClassDetail d) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildHeader(d),
          if (d.subjects.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: Text("No subjects set up for this class yet.", style: TextStyle(color: Colors.grey))),
            ),
          ...d.subjects.map((s) => Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${s.name} (${s.code})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text("Teacher: ${s.teacherName ?? 'Not assigned'}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 10),
                      _MetricBar(label: "Attendance", pct: s.attendancePct, color: attendanceColor(s.attendancePct), note: "${s.lectures} lectures"),
                      const SizedBox(height: 8),
                      _MetricBar(label: "Monday Test", pct: s.testPct, color: marksColor(s.testPct), note: "${s.tests} tests"),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// =====================================================================
// SMALL WIDGETS
// =====================================================================
class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatBox({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[700]), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _MetricBar extends StatelessWidget {
  final String label;
  final double? pct;
  final Color color;
  final String note;

  const _MetricBar({required this.label, required this.pct, required this.color, required this.note});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct == null ? 0.0 : (pct! / 100).clamp(0.0, 1.0).toDouble(),
              minHeight: 8,
              color: color,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Text(pctLabel(pct), textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ),
        const SizedBox(width: 6),
        SizedBox(width: 70, child: Text(note, style: const TextStyle(fontSize: 11, color: Colors.grey))),
      ],
    );
  }
}
