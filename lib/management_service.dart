import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestList;
import 'app_session.dart';

/// One account, as the management office sees it.
class ManagedUser {
  final String id;
  final String loginId;
  final String fullName;
  final String role; // 'student', 'faculty', 'admin', 'management'
  final String? designation;
  final int? departmentId;
  final int? classId;
  final bool isActive;

  const ManagedUser({
    required this.id,
    required this.loginId,
    required this.fullName,
    required this.role,
    required this.designation,
    required this.departmentId,
    required this.classId,
    required this.isActive,
  });

  factory ManagedUser.fromRow(Map<String, dynamic> r) => ManagedUser(
        id: r['id'] as String,
        loginId: (r['login_id'] ?? '') as String,
        fullName: (r['full_name'] ?? '') as String,
        role: (r['role'] ?? '') as String,
        designation: r['designation'] as String?,
        departmentId: (r['department_id'] as num?)?.toInt(),
        classId: (r['class_id'] as num?)?.toInt(),
        isActive: r['is_active'] != false,
      );
}

/// Everything the Management portal does. Creating and changing accounts
/// goes through database functions that check the management login.
class ManagementService {
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
  // READING
  // ------------------------------------------------------------------

  static Future<List<ManagedUser>> loadUsers(List<String> roles) async {
    final rows = await _fetchAll((from, to) => supabase
        .from('app_users')
        .select('id, login_id, full_name, role, designation, department_id, class_id, is_active')
        .inFilter('role', roles)
        .order('login_id', ascending: true)
        .range(from, to));
    return rows.map(ManagedUser.fromRow).toList();
  }

  static Future<Map<int, String>> loadDepartments() async {
    final rows = await supabase.from('departments').select('id, name').order('name', ascending: true);
    return {for (final r in rows) (r['id'] as num).toInt(): r['name'] as String};
  }

  /// id, name, department_id, class_teacher_id
  static Future<List<Map<String, dynamic>>> loadClasses() async {
    return await supabase
        .from('classes')
        .select('id, name, department_id, class_teacher_id')
        .order('name', ascending: true);
  }

  // ------------------------------------------------------------------
  // ACCOUNTS (each returns null when it worked, or an error to show)
  // ------------------------------------------------------------------

  static String? _errorFrom(dynamic res) {
    final map = res is Map ? res : const {};
    if (map['ok'] == true) return null;
    return (map['error'] ?? 'Something went wrong. Please try again.').toString();
  }

  static Future<String?> createUser({
    required String role,
    required String loginId,
    required String fullName,
    required String password,
    int? departmentId,
    int? classId,
    String? designation,
  }) async {
    final res = await supabase.rpc('mgmt_create_user', params: {
      'p_token': AppSession.token,
      'p_role': role,
      'p_login_id': loginId.trim(),
      'p_full_name': fullName.trim(),
      'p_password': password,
      'p_department_id': departmentId,
      'p_class_id': classId,
      'p_designation': designation,
    });
    return _errorFrom(res);
  }

  static Future<String?> updateUser({
    required String userId,
    required String loginId,
    required String fullName,
    int? departmentId,
    int? classId,
    String? designation,
    required bool isActive,
  }) async {
    final res = await supabase.rpc('mgmt_update_user', params: {
      'p_token': AppSession.token,
      'p_user_id': userId,
      'p_login_id': loginId.trim(),
      'p_full_name': fullName.trim(),
      'p_department_id': departmentId,
      'p_class_id': classId,
      'p_designation': designation,
      'p_is_active': isActive,
    });
    return _errorFrom(res);
  }

  static Future<String?> resetPassword({required String userId, required String newPassword}) async {
    final res = await supabase.rpc('mgmt_reset_password', params: {
      'p_token': AppSession.token,
      'p_user_id': userId,
      'p_new_password': newPassword,
    });
    return _errorFrom(res);
  }

  // ------------------------------------------------------------------
  // CLASSES AND DEPARTMENTS
  // ------------------------------------------------------------------

  static Future<void> addDepartment(String name) async {
    await supabase.from('departments').insert({'name': name.trim()});
  }

  static Future<void> addClass({required String name, required int departmentId, String? classTeacherId}) async {
    await supabase.from('classes').insert({
      'name': name.trim(),
      'department_id': departmentId,
      'class_teacher_id': classTeacherId,
    });
  }

  static Future<void> setClassTeacher(int classId, String? teacherId) async {
    await supabase.from('classes').update({'class_teacher_id': teacherId}).eq('id', classId);
  }

  // ------------------------------------------------------------------
  // HELPERS
  // ------------------------------------------------------------------

  /// A random 8-character password, without look-alike characters (0/O, 1/l).
  static String generatePassword() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final rnd = Random.secure();
    return List.generate(8, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  static String friendlyError(Object e) {
    final text = e.toString();
    if (text.contains('mgmt_') || text.contains('PGRST202')) {
      return 'The database needs the Phase 5 update. Run supabase_phase5.sql in the Supabase SQL Editor.';
    }
    if (text.contains('Only the management office')) {
      return 'Your login has expired. Please log out and log in again.';
    }
    if (text.contains('23505') || text.contains('duplicate')) {
      return 'That name is already used. Choose a different one.';
    }
    return 'Could not save. Check your internet connection and try again.';
  }
}
