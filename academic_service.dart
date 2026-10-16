import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_session.dart';
import 'leave_service.dart' show LeaveService;

/// One subject taught to one class, e.g. "CS-A - Data Structures".
class SubjectInfo {
  final int id;
  final String name;
  final String code;
  final int classId;
  final String className;
  final int? departmentId;
  final String departmentName;

  const SubjectInfo({
    required this.id,
    required this.name,
    required this.code,
    required this.classId,
    required this.className,
    required this.departmentId,
    required this.departmentName,
  });

  String get label => '$className - $name';
}

/// A student in a class list.
class ClassStudent {
  final String id;
  final String name;
  final String roll;

  const ClassStudent({required this.id, required this.name, required this.roll});
}

/// Everything needed for the attendance Excel report of one subject.
class AttendanceRegister {
  final List<ClassStudent> students;
  final List<Map<String, dynamic>> sessions; // id, lecture_date, time_slot (oldest first)
  final Map<int, Map<String, String>> statusBySession; // sessionId -> studentId -> 'P'/'A'

  const AttendanceRegister({required this.students, required this.sessions, required this.statusBySession});
}

/// One student's mark in one test.
class TestMark {
  final double? marks;
  final bool absent;
  const TestMark({required this.marks, required this.absent});
}

/// Everything needed for the Monday Test Excel report of one subject.
class TestRegister {
  final List<ClassStudent> students;
  final List<Map<String, dynamic>> tests; // id, title, test_date, max_marks (oldest first)
  final Map<int, Map<String, TestMark>> marksByTest; // testId -> studentId -> mark

  const TestRegister({required this.students, required this.tests, required this.marksByTest});
}

/// The logged-in student's subjects, attendance and test scores,
/// in the same shape the student dashboard already uses.
class StudentAcademicData {
  final List<Map<String, dynamic>> subjects; // name, code, total, attended
  final Map<String, List<Map<String, String>>> attendanceLogs; // code -> [date, status]
  final Map<String, List<Map<String, dynamic>>> testScores; // code -> [test, score, absent, max]

  const StudentAcademicData({required this.subjects, required this.attendanceLogs, required this.testScores});
}

class AcademicService {
  static double? _toDouble(dynamic v) => v == null ? null : (v as num).toDouble();

  /// Supabase returns at most 1000 rows per request, so long lists
  /// (a whole semester of attendance) are fetched page by page.
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

  // ------------------------------------------------------------------
  // SUBJECTS AND STUDENTS
  // ------------------------------------------------------------------

  /// Subjects assigned to one teacher.
  static Future<List<SubjectInfo>> loadFacultySubjects(String facultyId) async {
    final subjects = await supabase
        .from('subjects')
        .select('id, name, code, class_id')
        .eq('faculty_id', facultyId)
        .order('name', ascending: true);
    if (subjects.isEmpty) return [];

    final classIds = subjects.map((s) => s['class_id'] as int).toSet().toList();
    final classes = await supabase
        .from('classes')
        .select('id, name, department_id')
        .inFilter('id', classIds);
    final departments = await supabase.from('departments').select('id, name');

    final deptNames = {for (final d in departments) d['id'] as int: d['name'] as String};
    final classById = {for (final c in classes) c['id'] as int: c};

    final result = <SubjectInfo>[];
    for (final s in subjects) {
      final cls = classById[s['class_id'] as int];
      if (cls == null) continue;
      final deptId = cls['department_id'] as int?;
      result.add(SubjectInfo(
        id: s['id'] as int,
        name: s['name'] as String,
        code: s['code'] as String,
        classId: cls['id'] as int,
        className: cls['name'] as String,
        departmentId: deptId,
        departmentName: deptNames[deptId] ?? 'Other',
      ));
    }
    result.sort((a, b) => a.label.compareTo(b.label));
    return result;
  }

  /// Students of one class, sorted by roll number.
  static Future<List<ClassStudent>> loadStudents(int classId) async {
    final rows = await supabase
        .from('app_users')
        .select('id, full_name, login_id')
        .eq('role', 'student')
        .eq('class_id', classId)
        .order('login_id', ascending: true);
    return rows
        .map((r) => ClassStudent(
              id: r['id'] as String,
              name: r['full_name'] as String,
              roll: r['login_id'] as String,
            ))
        .toList();
  }

  // ------------------------------------------------------------------
  // ATTENDANCE
  // ------------------------------------------------------------------

  /// Attendance already saved for this lecture: studentId -> 'P'/'A'.
  /// Empty if this lecture hasn't been marked yet.
  static Future<Map<String, String>> loadExistingAttendance({
    required int subjectId,
    required DateTime date,
    required String timeSlot,
  }) async {
    final session = await supabase
        .from('attendance_sessions')
        .select('id')
        .eq('subject_id', subjectId)
        .eq('lecture_date', LeaveService.toDbDate(date))
        .eq('time_slot', timeSlot)
        .maybeSingle();
    if (session == null) return {};

    final records = await supabase
        .from('attendance_records')
        .select('student_id, status')
        .eq('session_id', session['id'] as int);
    return {for (final r in records) r['student_id'] as String: r['status'] as String};
  }

  /// Saves one lecture. Saving the same lecture again updates it.
  static Future<void> saveAttendance({
    required SubjectInfo subject,
    required String facultyId,
    required DateTime date,
    required String timeSlot,
    required Map<String, String> statusByStudent, // studentId -> 'P'/'A'
  }) async {
    final session = await supabase
        .from('attendance_sessions')
        .upsert({
          'subject_id': subject.id,
          'class_id': subject.classId,
          'faculty_id': facultyId,
          'lecture_date': LeaveService.toDbDate(date),
          'time_slot': timeSlot,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'subject_id,lecture_date,time_slot')
        .select('id')
        .single();

    final sessionId = session['id'] as int;
    if (statusByStudent.isEmpty) return;

    await supabase.from('attendance_records').upsert(
          statusByStudent.entries
              .map((e) => {'session_id': sessionId, 'student_id': e.key, 'status': e.value})
              .toList(),
          onConflict: 'session_id,student_id',
        );
  }

  /// All lectures and P/A marks of one subject, for the Excel report.
  static Future<AttendanceRegister> loadAttendanceRegister(SubjectInfo subject) async {
    final students = await loadStudents(subject.classId);
    final sessions = await supabase
        .from('attendance_sessions')
        .select('id, lecture_date, time_slot')
        .eq('subject_id', subject.id)
        .order('lecture_date', ascending: true)
        .order('time_slot', ascending: true);

    final statusBySession = <int, Map<String, String>>{};
    if (sessions.isNotEmpty) {
      final sessionIds = sessions.map((s) => s['id'] as int).toList();
      final records = await _fetchAll((from, to) => supabase
          .from('attendance_records')
          .select('session_id, student_id, status')
          .inFilter('session_id', sessionIds)
          .order('session_id', ascending: true)
          .order('student_id', ascending: true)
          .range(from, to));
      for (final r in records) {
        statusBySession.putIfAbsent(r['session_id'] as int, () => {})[r['student_id'] as String] =
            r['status'] as String;
      }
    }
    return AttendanceRegister(students: students, sessions: sessions, statusBySession: statusBySession);
  }

  // ------------------------------------------------------------------
  // MONDAY TESTS
  // ------------------------------------------------------------------

  /// Marks already saved for this subject's test on this date.
  static Future<Map<String, TestMark>> loadExistingTest({
    required int subjectId,
    required DateTime date,
  }) async {
    final test = await supabase
        .from('tests')
        .select('id')
        .eq('subject_id', subjectId)
        .eq('test_date', LeaveService.toDbDate(date))
        .maybeSingle();
    if (test == null) return {};

    final rows = await supabase
        .from('test_marks')
        .select('student_id, marks, absent')
        .eq('test_id', test['id'] as int);
    return {
      for (final r in rows)
        r['student_id'] as String: TestMark(marks: _toDouble(r['marks']), absent: r['absent'] as bool),
    };
  }

  /// Saves a Monday Test. A student with no marks (null) is saved as absent.
  /// Saving the same subject + date again updates it.
  static Future<void> saveTest({
    required SubjectInfo subject,
    required String facultyId,
    required DateTime date,
    required double maxMarks,
    required Map<String, double?> marksByStudent, // studentId -> marks (null = absent)
  }) async {
    final test = await supabase
        .from('tests')
        .upsert({
          'subject_id': subject.id,
          'class_id': subject.classId,
          'faculty_id': facultyId,
          'title': 'Monday Test',
          'test_date': LeaveService.toDbDate(date),
          'max_marks': maxMarks,
        }, onConflict: 'subject_id,test_date')
        .select('id')
        .single();

    final testId = test['id'] as int;
    if (marksByStudent.isEmpty) return;

    await supabase.from('test_marks').upsert(
          marksByStudent.entries
              .map((e) => {
                    'test_id': testId,
                    'student_id': e.key,
                    'marks': e.value,
                    'absent': e.value == null,
                  })
              .toList(),
          onConflict: 'test_id,student_id',
        );
  }

  /// All Monday Tests and marks of one subject, for the Excel report.
  static Future<TestRegister> loadTestRegister(SubjectInfo subject) async {
    final students = await loadStudents(subject.classId);
    final tests = await supabase
        .from('tests')
        .select('id, title, test_date, max_marks')
        .eq('subject_id', subject.id)
        .order('test_date', ascending: true);

    final marksByTest = <int, Map<String, TestMark>>{};
    if (tests.isNotEmpty) {
      final testIds = tests.map((t) => t['id'] as int).toList();
      final rows = await _fetchAll((from, to) => supabase
          .from('test_marks')
          .select('test_id, student_id, marks, absent')
          .inFilter('test_id', testIds)
          .order('test_id', ascending: true)
          .order('student_id', ascending: true)
          .range(from, to));
      for (final r in rows) {
        marksByTest.putIfAbsent(r['test_id'] as int, () => {})[r['student_id'] as String] =
            TestMark(marks: _toDouble(r['marks']), absent: r['absent'] as bool);
      }
    }
    return TestRegister(students: students, tests: tests, marksByTest: marksByTest);
  }

  // ------------------------------------------------------------------
  // STUDENT DASHBOARD
  // ------------------------------------------------------------------

  /// Short lecture label: 'L1: 09:00 - 09:50' -> 'L1'.
  static String shortSlot(String slot) {
    final i = slot.indexOf(':');
    return i > 0 ? slot.substring(0, i) : slot;
  }

  static Future<StudentAcademicData> loadStudentData(AppUser student) async {
    if (student.classId == null) {
      return const StudentAcademicData(subjects: [], attendanceLogs: {}, testScores: {});
    }

    final subjects = await supabase
        .from('subjects')
        .select('id, name, code')
        .eq('class_id', student.classId!)
        .order('code', ascending: true);

    final records = await _fetchAll((from, to) => supabase
        .from('attendance_records')
        .select('status, session:attendance_sessions(subject_id, lecture_date, time_slot)')
        .eq('student_id', student.id)
        .order('session_id', ascending: true)
        .range(from, to));

    final marks = await _fetchAll((from, to) => supabase
        .from('test_marks')
        .select('marks, absent, test:tests(subject_id, title, test_date, max_marks)')
        .eq('student_id', student.id)
        .order('test_id', ascending: true)
        .range(from, to));

    final codeBySubjectId = {for (final s in subjects) s['id'] as int: s['code'] as String};
    final total = <String, int>{};
    final attended = <String, int>{};
    final logsWithDate = <String, List<MapEntry<String, Map<String, String>>>>{};

    for (final r in records) {
      final session = r['session'] as Map<String, dynamic>?;
      if (session == null) continue;
      final code = codeBySubjectId[session['subject_id'] as int];
      if (code == null) continue;

      final isPresent = r['status'] == 'P';
      total[code] = (total[code] ?? 0) + 1;
      if (isPresent) attended[code] = (attended[code] ?? 0) + 1;

      final dbDate = session['lecture_date'].toString();
      final slot = session['time_slot'].toString();
      logsWithDate.putIfAbsent(code, () => []).add(MapEntry('$dbDate $slot', {
            'date': '${LeaveService.formatDbDate(dbDate)} (${shortSlot(slot)})',
            'status': isPresent ? 'Present' : 'Absent',
          }));
    }

    final testScores = <String, List<Map<String, dynamic>>>{};
    final testsWithDate = <String, List<MapEntry<String, Map<String, dynamic>>>>{};
    for (final m in marks) {
      final test = m['test'] as Map<String, dynamic>?;
      if (test == null) continue;
      final code = codeBySubjectId[test['subject_id'] as int];
      if (code == null) continue;

      final dbDate = test['test_date'].toString();
      testsWithDate.putIfAbsent(code, () => []).add(MapEntry(dbDate, {
            'test': '${test['title']} - ${LeaveService.formatDbDate(dbDate)}',
            'score': _toDouble(m['marks']) ?? 0.0,
            'absent': m['absent'] == true,
            'max': _toDouble(test['max_marks']) ?? 17.0,
          }));
    }

    // Newest lecture first in the day-by-day list; tests oldest first.
    final attendanceLogs = <String, List<Map<String, String>>>{};
    logsWithDate.forEach((code, entries) {
      entries.sort((a, b) => b.key.compareTo(a.key));
      attendanceLogs[code] = entries.map((e) => e.value).toList();
    });
    testsWithDate.forEach((code, entries) {
      entries.sort((a, b) => a.key.compareTo(b.key));
      testScores[code] = entries.map((e) => e.value).toList();
    });

    final subjectList = subjects
        .map((s) => <String, dynamic>{
              'name': s['name'] as String,
              'code': s['code'] as String,
              'total': total[s['code']] ?? 0,
              'attended': attended[s['code']] ?? 0,
            })
        .toList();

    return StudentAcademicData(subjects: subjectList, attendanceLogs: attendanceLogs, testScores: testScores);
  }
}
