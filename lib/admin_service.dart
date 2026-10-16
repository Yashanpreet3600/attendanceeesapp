import 'app_session.dart';
import 'academic_service.dart';

/// A faculty member with the subjects they teach.
class FacultyMember {
  final String id;
  final String name;
  final String loginId;
  final String? designation;
  final int? departmentId;
  final List<SubjectInfo> subjects;

  const FacultyMember({
    required this.id,
    required this.name,
    required this.loginId,
    required this.designation,
    required this.departmentId,
    required this.subjects,
  });
}

/// A subject of a class, for the "assign subject" list.
class ClassSubjectOption {
  final int id;
  final String name;
  final String code;
  final String? facultyId;
  final String? teacherName;

  const ClassSubjectOption({
    required this.id,
    required this.name,
    required this.code,
    required this.facultyId,
    required this.teacherName,
  });
}

class AdminService {
  /// All faculty, or one department's faculty, with their subjects.
  static Future<List<FacultyMember>> loadFaculty({int? departmentId}) async {
    final rows = departmentId == null
        ? await supabase
            .from('app_users')
            .select('id, full_name, login_id, designation, department_id')
            .eq('role', 'faculty')
            .order('full_name', ascending: true)
        : await supabase
            .from('app_users')
            .select('id, full_name, login_id, designation, department_id')
            .eq('role', 'faculty')
            .eq('department_id', departmentId)
            .order('full_name', ascending: true);
    if (rows.isEmpty) return [];

    final ids = rows.map((r) => r['id'] as String).toList();
    final subjects = await supabase
        .from('subjects')
        .select('id, name, code, class_id, faculty_id')
        .inFilter('faculty_id', ids)
        .order('name', ascending: true);
    final classes = await supabase.from('classes').select('id, name, department_id');
    final departments = await supabase.from('departments').select('id, name');

    final deptNames = {for (final d in departments) d['id'] as int: d['name'] as String};
    final classById = {for (final c in classes) c['id'] as int: c};

    final byFaculty = <String, List<SubjectInfo>>{};
    for (final s in subjects) {
      final cls = classById[s['class_id'] as int];
      if (cls == null) continue;
      final deptId = cls['department_id'] as int?;
      byFaculty.putIfAbsent(s['faculty_id'] as String, () => []).add(SubjectInfo(
            id: s['id'] as int,
            name: s['name'] as String,
            code: s['code'] as String,
            classId: cls['id'] as int,
            className: cls['name'] as String,
            departmentId: deptId,
            departmentName: deptNames[deptId] ?? 'Other',
          ));
    }

    return rows
        .map((r) => FacultyMember(
              id: r['id'] as String,
              name: r['full_name'] as String,
              loginId: r['login_id'] as String,
              designation: r['designation'] as String?,
              departmentId: r['department_id'] as int?,
              subjects: (byFaculty[r['id']] ?? [])..sort((a, b) => a.label.compareTo(b.label)),
            ))
        .toList();
  }

  /// All classes: id, name, department_id.
  static Future<List<Map<String, dynamic>>> loadClasses() async {
    return await supabase.from('classes').select('id, name, department_id').order('name', ascending: true);
  }

  /// Subjects of one class, with who teaches them now.
  static Future<List<ClassSubjectOption>> loadClassSubjects(int classId) async {
    final rows = await supabase
        .from('v_subject_summary')
        .select('subject_id, name, code, faculty_id, teacher_name')
        .eq('class_id', classId)
        .order('name', ascending: true);
    return rows
        .map((r) => ClassSubjectOption(
              id: (r['subject_id'] as num).toInt(),
              name: r['name'] as String,
              code: r['code'] as String,
              facultyId: r['faculty_id'] as String?,
              teacherName: r['teacher_name'] as String?,
            ))
        .toList();
  }

  /// Gives an existing subject to a teacher (moves it from any other teacher).
  static Future<void> assignSubject({required int subjectId, required String facultyId}) async {
    await supabase.from('subjects').update({'faculty_id': facultyId}).eq('id', subjectId);
  }

  /// Removes the teacher from a subject. The subject and its records stay.
  static Future<void> unassignSubject(int subjectId) async {
    await supabase.from('subjects').update({'faculty_id': null}).eq('id', subjectId);
  }

  /// Creates a new subject in a class and gives it to a teacher.
  static Future<void> createSubject({
    required int classId,
    required String name,
    required String code,
    String? facultyId,
  }) async {
    await supabase.from('subjects').insert({
      'class_id': classId,
      'name': name.trim(),
      'code': code.trim().toUpperCase(),
      'faculty_id': facultyId,
    });
  }
}
