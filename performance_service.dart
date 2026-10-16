import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_session.dart';
import 'academic_service.dart';

double _toDouble(dynamic v) => v == null ? 0.0 : (v as num).toDouble();
int _toInt(dynamic v) => v == null ? 0 : (v as num).toInt();

/// One class on the overview list (from the v_class_summary view).
class ClassSummary {
  final int classId;
  final String className;
  final int? departmentId;
  final String departmentName;
  final String? classTeacherName;
  final int students;
  final int lectures;
  final int tests;
  final int present;
  final int totalMarked;
  final double marksSum;
  final double maxSum;
  final int below75;

  const ClassSummary({
    required this.classId,
    required this.className,
    required this.departmentId,
    required this.departmentName,
    required this.classTeacherName,
    required this.students,
    required this.lectures,
    required this.tests,
    required this.present,
    required this.totalMarked,
    required this.marksSum,
    required this.maxSum,
    required this.below75,
  });

  /// null when no attendance has been marked yet
  double? get attendancePct => totalMarked == 0 ? null : present * 100 / totalMarked;

  /// null when no Monday Test marks have been uploaded yet
  double? get testPct => maxSum == 0 ? null : marksSum * 100 / maxSum;

  factory ClassSummary.fromRow(Map<String, dynamic> r) => ClassSummary(
        classId: _toInt(r['class_id']),
        className: (r['class_name'] ?? '') as String,
        departmentId: r['department_id'] == null ? null : _toInt(r['department_id']),
        departmentName: (r['department_name'] ?? 'Other') as String,
        classTeacherName: r['class_teacher_name'] as String?,
        students: _toInt(r['students']),
        lectures: _toInt(r['lectures']),
        tests: _toInt(r['tests']),
        present: _toInt(r['present']),
        totalMarked: _toInt(r['total_marked']),
        marksSum: _toDouble(r['marks_sum']),
        maxSum: _toDouble(r['max_sum']),
        below75: _toInt(r['below_75']),
      );
}

/// Attendance + Monday Test numbers for one student in one subject.
class StudentSubjectStat {
  int present = 0;
  int total = 0;
  int testsTaken = 0;
  int testsAbsent = 0;
  double marksSum = 0;
  double maxSum = 0;

  double? get attendancePct => total == 0 ? null : present * 100 / total;
  double? get testPct => maxSum == 0 ? null : marksSum * 100 / maxSum;
}

/// One subject of a class, with class-wide totals.
class SubjectPerformance {
  final int subjectId;
  final String name;
  final String code;
  final String? teacherName;
  final int lectures;
  final int tests;
  int present = 0;
  int totalMarked = 0;
  double marksSum = 0;
  double maxSum = 0;

  SubjectPerformance({
    required this.subjectId,
    required this.name,
    required this.code,
    required this.teacherName,
    required this.lectures,
    required this.tests,
  });

  double? get attendancePct => totalMarked == 0 ? null : present * 100 / totalMarked;
  double? get testPct => maxSum == 0 ? null : marksSum * 100 / maxSum;
}

/// One student of a class, with per-subject and overall numbers.
class StudentPerformance {
  final String id;
  final String name;
  final String roll;
  final Map<int, StudentSubjectStat> bySubject = {};

  StudentPerformance({required this.id, required this.name, required this.roll});

  int get present => bySubject.values.fold(0, (a, s) => a + s.present);
  int get totalMarked => bySubject.values.fold(0, (a, s) => a + s.total);
  int get testsTaken => bySubject.values.fold(0, (a, s) => a + s.testsTaken);
  int get testsAbsent => bySubject.values.fold(0, (a, s) => a + s.testsAbsent);
  double get _marks => bySubject.values.fold(0.0, (a, s) => a + s.marksSum);
  double get _max => bySubject.values.fold(0.0, (a, s) => a + s.maxSum);

  double? get attendancePct => totalMarked == 0 ? null : present * 100 / totalMarked;
  double? get testPct => _max == 0 ? null : _marks * 100 / _max;

  bool get lowAttendance => attendancePct != null && attendancePct! < 75;
  bool get lowMarks => testPct != null && testPct! < 35;
}

/// Everything shown on one class's performance screen.
class ClassDetail {
  final ClassSummary summary;
  final List<SubjectPerformance> subjects;
  final List<StudentPerformance> students;

  const ClassDetail({required this.summary, required this.subjects, required this.students});
}

class PerformanceService {
  static Future<List<Map<String, dynamic>>> _fetchAll(
    Future<PostgrestList> Function(int from, int to) page,
  ) async {
    const pageSize = 1000;
    final all = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final rows = await page(from, from + pageSize - 1);
      all.addAll(rows);
      if (rows.length < pageSize) break;
      from += pageSize;
    }
    return all;
  }

  /// Departments for the filter: id -> name.
  static Future<Map<int, String>> loadDepartments() async {
    final rows = await supabase.from('departments').select('id, name').order('name', ascending: true);
    return {for (final r in rows) _toInt(r['id']): r['name'] as String};
  }

  /// All classes, or only one department's classes.
  static Future<List<ClassSummary>> loadClassSummaries({int? departmentId}) async {
    final rows = departmentId == null
        ? await supabase.from('v_class_summary').select().order('class_name', ascending: true)
        : await supabase
            .from('v_class_summary')
            .select()
            .eq('department_id', departmentId)
            .order('class_name', ascending: true);
    return rows.map(ClassSummary.fromRow).toList();
  }

  /// Subjects and students of one class, with their numbers.
  static Future<ClassDetail?> loadClassDetail(int classId) async {
    final summaryRow = await supabase.from('v_class_summary').select().eq('class_id', classId).maybeSingle();
    if (summaryRow == null) return null;

    final subjectRows = await supabase
        .from('v_subject_summary')
        .select()
        .eq('class_id', classId)
        .order('code', ascending: true);
    final classStudents = await AcademicService.loadStudents(classId);

    final attendanceRows = await _fetchAll((from, to) => supabase
        .from('v_student_subject_attendance')
        .select()
        .eq('class_id', classId)
        .order('student_id', ascending: true)
        .order('subject_id', ascending: true)
        .range(from, to));
    final testRows = await _fetchAll((from, to) => supabase
        .from('v_student_subject_tests')
        .select()
        .eq('class_id', classId)
        .order('student_id', ascending: true)
        .order('subject_id', ascending: true)
        .range(from, to));

    final subjects = <int, SubjectPerformance>{
      for (final r in subjectRows)
        _toInt(r['subject_id']): SubjectPerformance(
          subjectId: _toInt(r['subject_id']),
          name: r['name'] as String,
          code: r['code'] as String,
          teacherName: r['teacher_name'] as String?,
          lectures: _toInt(r['lectures']),
          tests: _toInt(r['tests']),
        ),
    };
    final students = <String, StudentPerformance>{
      for (final s in classStudents) s.id: StudentPerformance(id: s.id, name: s.name, roll: s.roll),
    };

    for (final r in attendanceRows) {
      final student = students[r['student_id']];
      final subjectId = _toInt(r['subject_id']);
      final subject = subjects[subjectId];
      final present = _toInt(r['present']);
      final total = _toInt(r['total']);
      if (subject != null) {
        subject.present += present;
        subject.totalMarked += total;
      }
      if (student != null) {
        final stat = student.bySubject.putIfAbsent(subjectId, () => StudentSubjectStat());
        stat.present += present;
        stat.total += total;
      }
    }

    for (final r in testRows) {
      final student = students[r['student_id']];
      final subjectId = _toInt(r['subject_id']);
      final subject = subjects[subjectId];
      final marks = _toDouble(r['marks_sum']);
      final max = _toDouble(r['max_sum']);
      if (subject != null) {
        subject.marksSum += marks;
        subject.maxSum += max;
      }
      if (student != null) {
        final stat = student.bySubject.putIfAbsent(subjectId, () => StudentSubjectStat());
        stat.testsTaken += _toInt(r['taken']);
        stat.testsAbsent += _toInt(r['absent']);
        stat.marksSum += marks;
        stat.maxSum += max;
      }
    }

    return ClassDetail(
      summary: ClassSummary.fromRow(summaryRow),
      subjects: subjects.values.toList(),
      students: students.values.toList(),
    );
  }
}
