import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'app_session.dart';

/// A teacher a student can send a leave request to.
class LeaveRecipient {
  final String teacherId;
  final String teacherName;
  final String role; // 'Class In-charge' or 'HOD'

  const LeaveRecipient({
    required this.teacherId,
    required this.teacherName,
    required this.role,
  });

  String get label => '$role - $teacherName';
}

/// Everything related to leave requests in Supabase.
class LeaveService {
  static const String _table = 'leave_requests';

  /// Finds who this student can send leave to:
  /// their class in-charge and their department's HOD.
  static Future<List<LeaveRecipient>> loadRecipients(AppUser student) async {
    final recipients = <LeaveRecipient>[];

    // 1. Class in-charge
    if (student.classId != null) {
      final cls = await supabase
          .from('classes')
          .select('class_teacher_id')
          .eq('id', student.classId!)
          .maybeSingle();
      final teacherId = cls?['class_teacher_id'] as String?;

      if (teacherId != null) {
        final teacher = await supabase
            .from('app_users')
            .select('id, full_name')
            .eq('id', teacherId)
            .maybeSingle();
        if (teacher != null) {
          recipients.add(LeaveRecipient(
            teacherId: teacher['id'] as String,
            teacherName: teacher['full_name'] as String,
            role: 'Class In-charge',
          ));
        }
      }
    }

    // 2. HOD of the student's department
    if (student.departmentId != null) {
      final hods = await supabase
          .from('app_users')
          .select('id, full_name')
          .eq('role', 'faculty')
          .eq('designation', 'HOD')
          .eq('department_id', student.departmentId!)
          .limit(1);

      for (final hod in hods) {
        final alreadyListed = recipients.any((r) => r.teacherId == hod['id']);
        if (!alreadyListed) {
          recipients.add(LeaveRecipient(
            teacherId: hod['id'] as String,
            teacherName: hod['full_name'] as String,
            role: 'HOD',
          ));
        }
      }
    }

    return recipients;
  }

  // ------------------------------------------------------------------
  // PHOTO ATTACHMENT (medical certificate) - Supabase Storage
  // ------------------------------------------------------------------

  static const String attachmentBucket = 'leave-attachments';
  static const int maxAttachmentBytes = 5 * 1024 * 1024; // 5 MB

  /// Uploads a photo and returns its storage path.
  static Future<String> uploadAttachment(String studentId, Uint8List bytes) async {
    // Work out the image type from the file's first bytes
    var ext = 'jpg';
    var mime = 'image/jpeg';
    if (bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50) {
      ext = 'png';
      mime = 'image/png';
    } else if (bytes.length > 12 && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      ext = 'webp';
      mime = 'image/webp';
    }
    final path = '$studentId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await supabase.storage
        .from(attachmentBucket)
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime, upsert: false));
    return path;
  }

  /// A link to view the photo, valid for one hour.
  static Future<String> attachmentUrl(String path) {
    return supabase.storage.from(attachmentBucket).createSignedUrl(path, 3600);
  }

  /// Saves a new leave request with status 'Pending'.
  /// [attachment] is an optional photo (medical certificate).
  static Future<void> applyLeave({
    required AppUser student,
    required LeaveRecipient recipient,
    required DateTime fromDate,
    required DateTime toDate,
    required String reason,
    Uint8List? attachment,
  }) async {
    final String? attachmentPath =
        attachment == null ? null : await uploadAttachment(student.id, attachment);

    await supabase.from(_table).insert({
      'student_id': student.id,
      'student_name': student.fullName,
      'student_roll': student.loginId,
      'class_name': student.className,
      'teacher_id': recipient.teacherId,
      'teacher_name': recipient.teacherName,
      'sent_to': recipient.role,
      'from_date': toDbDate(fromDate),
      'to_date': toDbDate(toDate),
      'reason': reason.trim(),
      if (attachmentPath != null) 'attachment_path': attachmentPath,
    });
  }

  /// Live list of one student's leave requests, newest first.
  /// Updates by itself when a teacher approves or rejects.
  static Stream<List<Map<String, dynamic>>> streamForStudent(String studentId) {
    return supabase
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('student_id', studentId)
        .order('created_at');
  }

  /// Live list of leave requests sent to one teacher, newest first.
  /// New requests appear by themselves.
  static Stream<List<Map<String, dynamic>>> streamForTeacher(String teacherId) {
    return supabase
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('teacher_id', teacherId)
        .order('created_at');
  }

  /// Approves or rejects a request.
  static Future<void> review({
    required int leaveId,
    required bool approve,
    required String remark,
  }) async {
    final cleanRemark = remark.trim();
    await supabase.from(_table).update({
      'status': approve ? 'Approved' : 'Rejected',
      'remark': cleanRemark.isEmpty ? null : cleanRemark,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', leaveId);
  }

  // ------------------------------------------------------------------
  // DATE HELPERS
  // ------------------------------------------------------------------

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// 2026-10-20 format, used by the database.
  static String toDbDate(DateTime d) {
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  /// "20 Oct 2026" format, shown in the app.
  static String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  static String formatDbDate(dynamic value) {
    final d = value == null ? null : DateTime.tryParse(value.toString());
    return d == null ? '-' : formatDate(d);
  }

  /// "20 Oct 2026" or "20 Oct 2026 - 22 Oct 2026 (3 days)".
  static String formatRange(Map<String, dynamic> leave) {
    final from = DateTime.tryParse(leave['from_date'].toString());
    final to = DateTime.tryParse(leave['to_date'].toString());
    if (from == null || to == null) return '-';
    if (from == to) return formatDate(from);
    final days = to.difference(from).inDays + 1;
    return '${formatDate(from)} - ${formatDate(to)} ($days days)';
  }
}
