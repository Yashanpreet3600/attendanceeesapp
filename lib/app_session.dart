import 'package:supabase_flutter/supabase_flutter.dart';

/// Shortcut to the Supabase client, used by every screen.
SupabaseClient get supabase => Supabase.instance.client;

/// The person who is currently logged in.
class AppUser {
  final String id; // uuid from the app_users table
  final String loginId; // roll number or staff ID, e.g. 2501 or FAC-002
  final String fullName;
  final String role; // 'student', 'faculty' or 'admin'
  final String? designation; // 'HOD', 'Assistant Prof', ...
  final int? departmentId;
  final String? departmentName;
  final int? classId; // students only
  final String? className; // students only

  const AppUser({
    required this.id,
    required this.loginId,
    required this.fullName,
    required this.role,
    this.designation,
    this.departmentId,
    this.departmentName,
    this.classId,
    this.className,
  });
}

/// Result of a login attempt.
class LoginResult {
  final AppUser? user;
  final bool mustChangePassword; // first login, or password was reset
  final String? failure; // 'wrong' or 'disabled'

  const LoginResult({this.user, this.mustChangePassword = false, this.failure});
}

/// Keeps the logged-in user in memory while the app is open.
///
/// Login checks the password in the database (Phase 5). Passwords are
/// stored encrypted and the app can never read them. A login returns a
/// session token, used for changing passwords and management actions.
class AppSession {
  static AppUser? currentUser;
  static String? token;

  /// Checks ID + role + password. Throws if the server can't be reached.
  static Future<LoginResult> signIn({
    required String loginId,
    required String role,
    required String password,
  }) async {
    final res = await supabase.rpc('app_login', params: {
      'p_login_id': loginId.trim(),
      'p_role': role,
      'p_password': password,
    });
    final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    if (map['ok'] != true) {
      return LoginResult(failure: (map['reason'] ?? 'wrong').toString());
    }

    final row = Map<String, dynamic>.from(map['user'] as Map);
    final int? departmentId = (row['department_id'] as num?)?.toInt();
    final int? classId = (row['class_id'] as num?)?.toInt();

    String? departmentName;
    if (departmentId != null) {
      final dept = await supabase.from('departments').select('name').eq('id', departmentId).maybeSingle();
      departmentName = dept?['name'] as String?;
    }

    String? className;
    if (classId != null) {
      final cls = await supabase.from('classes').select('name').eq('id', classId).maybeSingle();
      className = cls?['name'] as String?;
    }

    token = map['token'] as String?;
    currentUser = AppUser(
      id: row['id'] as String,
      loginId: row['login_id'] as String,
      fullName: row['full_name'] as String,
      role: row['role'] as String,
      designation: row['designation'] as String?,
      departmentId: departmentId,
      departmentName: departmentName,
      classId: classId,
      className: className,
    );
    return LoginResult(user: currentUser, mustChangePassword: map['must_change'] == true);
  }

  /// Returns null when the password was changed, or an error to show.
  static Future<String?> changePassword(String oldPassword, String newPassword) async {
    final res = await supabase.rpc('app_change_password', params: {
      'p_token': token,
      'p_old_password': oldPassword,
      'p_new_password': newPassword,
    });
    final map = res is Map ? res : const {};
    if (map['ok'] == true) return null;
    return (map['error'] ?? 'Could not change the password.').toString();
  }

  static void signOut() {
    final oldToken = token;
    token = null;
    currentUser = null;
    if (oldToken != null) {
      // End the session on the server too (ignore errors, e.g. no internet)
      supabase.rpc('app_logout', params: {'p_token': oldToken}).then((_) {}, onError: (_) {});
    }
  }
}
