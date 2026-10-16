import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart'
    show RealtimeChannel, PostgresChangeEvent, PostgresChangeFilter, PostgresChangeFilterType;

import 'app_session.dart';
import 'leave_service.dart' show LeaveService;

// =====================================================================
// MESSAGES - works like leave requests:
//   1. The sender sends a message. The database delivers it to every
//      person it is meant for (one "delivery" row each).
//   2. The recipient sees it in their inbox, opens it (= marked read)
//      and can reply.
//   3. The sender sees "Delivered to 5, read by 3" and every reply,
//      and can reply back.
// Tables: messages, message_recipients, message_replies (Phase 4 SQL)
// =====================================================================

DateTime? _parseTime(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// One message in someone's inbox.
class InboxItem {
  final int rowId; // message_recipients.id (this person's copy)
  final int messageId;
  final String title;
  final String body;
  final String priority;
  final String senderName;
  final String senderRole; // 'faculty' or 'admin'
  final DateTime? sentAt;
  final DateTime? readAt;
  final int replyCount;
  final bool newReplyFromSender;

  const InboxItem({
    required this.rowId,
    required this.messageId,
    required this.title,
    required this.body,
    required this.priority,
    required this.senderName,
    required this.senderRole,
    required this.sentAt,
    required this.readAt,
    required this.replyCount,
    required this.newReplyFromSender,
  });

  bool get isRead => readAt != null;
  bool get isUnread => !isRead || newReplyFromSender;
  bool get isImportant => priority == 'High';
  String get fromLabel => senderRole == 'admin' ? '$senderName (Admin)' : senderName;

  factory InboxItem.fromRow(Map<String, dynamic> r) {
    final m = (r['message'] as Map<String, dynamic>?) ?? const {};
    final lastReply = _parseTime(r['last_reply_at']);
    final seen = _parseTime(r['recipient_seen_at']);
    return InboxItem(
      rowId: (r['id'] as num).toInt(),
      messageId: (r['message_id'] as num).toInt(),
      title: (m['title'] ?? '') as String,
      body: (m['body'] ?? '') as String,
      priority: (m['priority'] ?? 'Normal') as String,
      senderName: (m['sender_name'] ?? '') as String,
      senderRole: (m['sender_role'] ?? 'faculty') as String,
      sentAt: _parseTime(m['created_at']),
      readAt: _parseTime(r['read_at']),
      replyCount: (r['reply_count'] as num?)?.toInt() ?? 0,
      newReplyFromSender: r['last_reply_by_sender'] == true &&
          lastReply != null &&
          (seen == null || lastReply.isAfter(seen)),
    );
  }
}

/// One message in the sender's Sent list.
class SentItem {
  final int messageId;
  final String title;
  final String body;
  final String priority;
  final String toLabel;
  final DateTime? sentAt;
  final int delivered;
  final int readCount;
  final int conversations;
  final int newReplies;

  const SentItem({
    required this.messageId,
    required this.title,
    required this.body,
    required this.priority,
    required this.toLabel,
    required this.sentAt,
    required this.delivered,
    required this.readCount,
    required this.conversations,
    required this.newReplies,
  });

  bool get isImportant => priority == 'High';
}

/// One recipient of a sent message (for "who has read it").
class RecipientStatus {
  final int rowId;
  final String name;
  final String role;
  final DateTime? readAt;
  final int replyCount;
  final bool newReplyForSender;

  const RecipientStatus({
    required this.rowId,
    required this.name,
    required this.role,
    required this.readAt,
    required this.replyCount,
    required this.newReplyForSender,
  });

  bool get isRead => readAt != null;
}

/// One reply in a conversation.
class ReplyItem {
  final int id;
  final String authorName;
  final bool authorIsSender;
  final String body;
  final DateTime? createdAt;

  const ReplyItem({
    required this.id,
    required this.authorName,
    required this.authorIsSender,
    required this.body,
    required this.createdAt,
  });
}

class MessageService {
  static const String _inboxSelect =
      'id, message_id, read_at, reply_count, last_reply_at, last_reply_by_sender, recipient_seen_at, '
      'message:messages(title, body, priority, sender_name, sender_role, created_at)';

  // ------------------------------------------------------------------
  // SENDING
  // ------------------------------------------------------------------

  /// Sends a message and returns how many people it was delivered to.
  static Future<int> send({
    required AppUser sender,
    required String audience, // 'students', 'faculty' or 'admin'
    required String title,
    required String body,
    String priority = 'Normal', // 'Normal' or 'High'
    int? departmentId,
    int? classId,
    String? studentId,
    String? facultyId,
    String? targetLabel, // shown as "To: ..." in the Sent list
  }) async {
    final result = await supabase.rpc('send_message', params: {
      'p_sender_id': sender.id,
      'p_audience': audience,
      'p_title': title.trim(),
      'p_body': body.trim(),
      'p_priority': priority,
      'p_department_id': departmentId,
      'p_class_id': classId,
      'p_student_id': studentId,
      'p_faculty_id': facultyId,
      'p_target_label': targetLabel,
    });
    if (result is Map && result['delivered'] is num) return (result['delivered'] as num).toInt();
    return 0;
  }

  // ------------------------------------------------------------------
  // INBOX (for the person receiving messages)
  // ------------------------------------------------------------------

  static Future<List<InboxItem>> loadInbox(String userId) async {
    final rows = await supabase
        .from('message_recipients')
        .select(_inboxSelect)
        .eq('recipient_id', userId)
        .order('created_at', ascending: false)
        .limit(300);
    return rows.map(InboxItem.fromRow).toList();
  }

  /// Opening a message marks it read.
  static Future<void> markRead(int rowId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await supabase.from('message_recipients').update({'recipient_seen_at': now}).eq('id', rowId);
    await supabase.from('message_recipients').update({'read_at': now}).eq('id', rowId).isFilter('read_at', null);
  }

  static Future<void> markAllRead(String userId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await supabase
        .from('message_recipients')
        .update({'read_at': now, 'recipient_seen_at': now})
        .eq('recipient_id', userId)
        .isFilter('read_at', null);
  }

  // ------------------------------------------------------------------
  // SENT (for the person who sent messages)
  // ------------------------------------------------------------------

  static Future<List<SentItem>> loadSent(String userId) async {
    final messages = await supabase
        .from('messages')
        .select('id, title, body, priority, target_label, audience, faculty_id, student_id, class_id, department_id, created_at')
        .eq('sender_id', userId)
        .order('created_at', ascending: false)
        .limit(200);
    if (messages.isEmpty) return [];

    final ids = messages.map((m) => (m['id'] as num).toInt()).toList();
    final stats = await supabase.from('v_message_stats').select().inFilter('message_id', ids);
    final statsById = {for (final s in stats) (s['message_id'] as num).toInt(): s};

    return messages.map((m) {
      final id = (m['id'] as num).toInt();
      final s = statsById[id] ?? const <String, dynamic>{};
      return SentItem(
        messageId: id,
        title: (m['title'] ?? '') as String,
        body: (m['body'] ?? '') as String,
        priority: (m['priority'] ?? 'Normal') as String,
        toLabel: recipientLabel(m),
        sentAt: _parseTime(m['created_at']),
        delivered: (s['delivered'] as num?)?.toInt() ?? 0,
        readCount: (s['read_count'] as num?)?.toInt() ?? 0,
        conversations: (s['conversations'] as num?)?.toInt() ?? 0,
        newReplies: (s['new_replies'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  /// Everyone a message was delivered to, with read and reply status.
  static Future<List<RecipientStatus>> loadRecipients(int messageId) async {
    final rows = await supabase
        .from('message_recipients')
        .select('id, recipient_name, recipient_role, read_at, reply_count, last_reply_at, last_reply_by_sender, sender_seen_at')
        .eq('message_id', messageId)
        .order('recipient_name', ascending: true);
    return rows.map((r) {
      final lastReply = _parseTime(r['last_reply_at']);
      final seen = _parseTime(r['sender_seen_at']);
      return RecipientStatus(
        rowId: (r['id'] as num).toInt(),
        name: (r['recipient_name'] ?? '') as String,
        role: (r['recipient_role'] ?? '') as String,
        readAt: _parseTime(r['read_at']),
        replyCount: (r['reply_count'] as num?)?.toInt() ?? 0,
        newReplyForSender: r['last_reply_by_sender'] == false &&
            lastReply != null &&
            (seen == null || lastReply.isAfter(seen)),
      );
    }).toList();
  }

  /// The sender opened a conversation: clears its "new reply" mark.
  static Future<void> markSenderSeen(int rowId) async {
    await supabase
        .from('message_recipients')
        .update({'sender_seen_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', rowId);
  }

  // ------------------------------------------------------------------
  // REPLIES (a private conversation between the sender and one recipient)
  // ------------------------------------------------------------------

  static Future<List<ReplyItem>> loadReplies(int rowId) async {
    final rows = await supabase
        .from('message_replies')
        .select('id, author_name, author_is_sender, body, created_at')
        .eq('recipient_row_id', rowId)
        .order('created_at', ascending: true);
    return rows
        .map((r) => ReplyItem(
              id: (r['id'] as num).toInt(),
              authorName: (r['author_name'] ?? '') as String,
              authorIsSender: r['author_is_sender'] == true,
              body: (r['body'] ?? '') as String,
              createdAt: _parseTime(r['created_at']),
            ))
        .toList();
  }

  static Future<void> reply({
    required int rowId,
    required AppUser author,
    required bool authorIsSender,
    required String body,
  }) async {
    await supabase.from('message_replies').insert({
      'recipient_row_id': rowId,
      'author_id': author.id,
      'author_name': author.fullName,
      'author_is_sender': authorIsSender,
      'body': body.trim(),
    });
  }

  // ------------------------------------------------------------------
  // LIVE UPDATES
  // ------------------------------------------------------------------

  static int _channelCount = 0;

  /// Calls [onChange] whenever a row in [table] with [column] = [value] changes.
  static RealtimeChannel watch(String table, String column, Object value, void Function() onChange) {
    _channelCount++;
    return supabase
        .channel('watch-$table-$column-$value-$_channelCount')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: column, value: value),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  static Future<void> stopWatching(RealtimeChannel? channel) async {
    if (channel == null) return;
    try {
      await supabase.removeChannel(channel);
    } catch (e) {
      debugPrint('Remove channel error: $e');
    }
  }

  // ------------------------------------------------------------------
  // HELPERS
  // ------------------------------------------------------------------

  /// "To:" text for a message, using the saved label when there is one.
  static String recipientLabel(Map<String, dynamic> m) {
    final label = m['target_label'] as String?;
    if (label != null && label.isNotEmpty) return label;
    switch (m['audience']) {
      case 'admin':
        return 'Admin Office';
      case 'faculty':
        return m['faculty_id'] != null ? 'One faculty member' : 'Faculty';
      default:
        if (m['student_id'] != null) return 'One student';
        if (m['class_id'] != null) return 'A class';
        if (m['department_id'] != null) return 'A department';
        return 'All students';
    }
  }

  /// A clear message for a failed send or reply.
  static String friendlyError(Object e) {
    final text = e.toString();
    if (text.contains('send_message') ||
        text.contains('message_recipients') ||
        text.contains('message_replies') ||
        text.contains('PGRST202') ||
        text.contains('PGRST205')) {
      return 'The database needs the Phase 4 update. Run supabase_phase4.sql in the Supabase SQL Editor, then try again.';
    }
    return 'Could not send. Check your internet connection and try again.';
  }

  /// "just now", "5 min ago", "3 hrs ago", "2 days ago" or a date.
  static String timeAgo(DateTime? time) {
    if (time == null) return '';
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr${diff.inHours == 1 ? '' : 's'} ago';
    if (diff.inDays < 7) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    return LeaveService.formatDate(time);
  }
}

// =====================================================================
// INBOX CONTROLLER
// Keeps one person's inbox up to date: loads it, listens for live
// changes, and also refreshes every 20 seconds as a backup.
// =====================================================================
class InboxController extends ChangeNotifier {
  final String userId;
  final void Function(InboxItem newest)? onNewMessage;

  List<InboxItem> items = [];
  bool loaded = false;
  String? error;

  RealtimeChannel? _channel;
  Timer? _timer;
  final Set<int> _known = {};
  bool _first = true;
  bool _disposed = false;
  bool _loading = false;
  bool _again = false;

  InboxController({required this.userId, this.onNewMessage});

  int get unreadCount => items.where((i) => i.isUnread).length;

  void start() {
    refresh();
    _channel = MessageService.watch('message_recipients', 'recipient_id', userId, refresh);
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (_loading) {
      _again = true; // a change arrived while loading: load once more after
      return;
    }
    _loading = true;
    try {
      final list = await MessageService.loadInbox(userId);
      if (_disposed) return;
      if (!_first && onNewMessage != null) {
        final fresh = list.where((i) => !_known.contains(i.rowId)).toList();
        if (fresh.isNotEmpty) onNewMessage!(fresh.first);
      }
      _first = false;
      _known
        ..clear()
        ..addAll(list.map((i) => i.rowId));
      items = list;
      loaded = true;
      error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Inbox load error: $e');
      if (_disposed) return;
      error = MessageService.friendlyError(e).replaceFirst('Could not send', 'Could not load messages');
      loaded = true;
      notifyListeners();
    } finally {
      _loading = false;
      if (_again && !_disposed) {
        _again = false;
        refresh();
      }
    }
  }

  Future<void> markAllRead() async {
    await MessageService.markAllRead(userId);
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    MessageService.stopWatching(_channel);
    super.dispose();
  }
}

// =====================================================================
// SENT CONTROLLER
// Keeps the sender's Sent list (delivered / read / replies) up to date.
// =====================================================================
class SentController extends ChangeNotifier {
  final String userId;

  List<SentItem> items = [];
  bool loaded = false;
  String? error;

  RealtimeChannel? _channel;
  Timer? _timer;
  bool _disposed = false;
  bool _loading = false;
  bool _again = false;

  SentController({required this.userId});

  int get newReplies => items.fold(0, (a, i) => a + i.newReplies);

  void start() {
    refresh();
    // Fires when anyone reads or replies to one of this person's messages
    _channel = MessageService.watch('message_recipients', 'sender_id', userId, refresh);
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (_loading) {
      _again = true; // a change arrived while loading: load once more after
      return;
    }
    _loading = true;
    try {
      final list = await MessageService.loadSent(userId);
      if (_disposed) return;
      items = list;
      loaded = true;
      error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Sent list load error: $e');
      if (_disposed) return;
      error = 'Could not load sent messages. Check your internet connection.';
      loaded = true;
      notifyListeners();
    } finally {
      _loading = false;
      if (_again && !_disposed) {
        _again = false;
        refresh();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    MessageService.stopWatching(_channel);
    super.dispose();
  }
}
