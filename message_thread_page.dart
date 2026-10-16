import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'app_session.dart';
import 'message_service.dart';

const Color _navy = Color(0xFF002046);

// =====================================================================
// CONVERSATION: the original message + replies between the sender and
// one recipient. Used by both sides:
//   viewerIsSender = false -> the recipient (opening it marks it read)
//   viewerIsSender = true  -> the sender, looking at one recipient
// =====================================================================
class MessageThreadPage extends StatefulWidget {
  final int rowId; // message_recipients.id
  final String title;
  final String body;
  final String priority;
  final DateTime? sentAt;
  final String senderName;
  final String otherPartyName; // who you are talking to
  final bool viewerIsSender;
  final DateTime? readAt; // shown to the sender

  const MessageThreadPage({
    super.key,
    required this.rowId,
    required this.title,
    required this.body,
    required this.priority,
    required this.sentAt,
    required this.senderName,
    required this.otherPartyName,
    required this.viewerIsSender,
    this.readAt,
  });

  /// Opens a message from the inbox.
  factory MessageThreadPage.fromInbox(InboxItem item) => MessageThreadPage(
        rowId: item.rowId,
        title: item.title,
        body: item.body,
        priority: item.priority,
        sentAt: item.sentAt,
        senderName: item.fromLabel,
        otherPartyName: item.fromLabel,
        viewerIsSender: false,
      );

  @override
  State<MessageThreadPage> createState() => _MessageThreadPageState();
}

class _MessageThreadPageState extends State<MessageThreadPage> {
  final AppUser? me = AppSession.currentUser;
  final TextEditingController _replyCtrl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<ReplyItem> _replies = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  RealtimeChannel? _channel;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _markSeen();
    _load();
    _channel = MessageService.watch('message_replies', 'recipient_row_id', widget.rowId, _load);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    MessageService.stopWatching(_channel);
    _replyCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _markSeen() async {
    try {
      if (widget.viewerIsSender) {
        await MessageService.markSenderSeen(widget.rowId);
      } else {
        await MessageService.markRead(widget.rowId);
      }
    } catch (e) {
      debugPrint('Mark seen error: $e');
    }
  }

  Future<void> _load() async {
    try {
      final list = await MessageService.loadReplies(widget.rowId);
      if (!mounted) return;
      final hadNew = list.length > _replies.length;
      setState(() {
        _replies = list;
        _loading = false;
        _error = null;
      });
      if (hadNew) {
        _markSeen();
        _scrollToEnd();
      }
    } catch (e) {
      debugPrint('Load replies error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load replies. Check your internet connection.';
        });
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final user = me;
    final text = _replyCtrl.text.trim();
    if (user == null || text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await MessageService.reply(
        rowId: widget.rowId,
        author: user,
        authorIsSender: widget.viewerIsSender,
        body: text,
      );
      _replyCtrl.clear();
      await _load();
    } catch (e) {
      debugPrint('Reply error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(MessageService.friendlyError(e)),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHigh = widget.priority == 'High';
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 17), overflow: TextOverflow.ellipsis),
            Text(
              widget.viewerIsSender ? "Conversation with ${widget.otherPartyName}" : "From ${widget.senderName}",
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(14),
              children: [
                // --- The original message ---
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: isHigh ? Colors.red.withOpacity(0.4) : Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(widget.title,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navy)),
                            ),
                            if (isHigh)
                              const Text("Important",
                                  style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Text("${widget.senderName}  |  ${MessageService.timeAgo(widget.sentAt)}",
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        const Divider(),
                        Text(widget.body, style: const TextStyle(fontSize: 15)),
                        if (widget.viewerIsSender) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(widget.readAt != null ? Icons.done_all : Icons.done,
                                  size: 16, color: widget.readAt != null ? Colors.blue : Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                widget.readAt != null
                                    ? "Read by ${widget.otherPartyName} ${MessageService.timeAgo(widget.readAt)}"
                                    : "Delivered, not read yet",
                                style: TextStyle(fontSize: 12, color: widget.readAt != null ? Colors.blue : Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_loading)
                  const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                else if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center)
                else if (_replies.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      widget.viewerIsSender
                          ? "No replies from ${widget.otherPartyName} yet."
                          : "No replies yet. Write a reply below if you want to answer.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ..._replies.map(_buildBubble),
              ],
            ),
          ),

          // --- Reply box ---
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, -2))],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyCtrl,
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: "Reply to ${widget.otherPartyName}...",
                        counterText: "",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    style: IconButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white),
                    icon: _sending
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(ReplyItem r) {
    final mine = r.authorIsSender == widget.viewerIsSender;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine ? _navy : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14.0 : 2.0),
            bottomRight: Radius.circular(mine ? 2.0 : 14.0),
          ),
          border: mine ? null : Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(r.authorName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navy)),
            Text(r.body, style: TextStyle(color: mine ? Colors.white : Colors.black87, fontSize: 14)),
            const SizedBox(height: 2),
            Text(MessageService.timeAgo(r.createdAt),
                style: TextStyle(fontSize: 10, color: mine ? Colors.white60 : Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// SENT MESSAGE: who it was delivered to, who has read it, and replies
// =====================================================================
class SentMessagePage extends StatefulWidget {
  final SentItem item;
  const SentMessagePage({super.key, required this.item});

  @override
  State<SentMessagePage> createState() => _SentMessagePageState();
}

class _SentMessagePageState extends State<SentMessagePage> {
  final AppUser? me = AppSession.currentUser;
  List<RecipientStatus> _recipients = [];
  bool _loading = true;
  String? _error;
  RealtimeChannel? _channel;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = MessageService.watch('message_recipients', 'message_id', widget.item.messageId, _load);
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    MessageService.stopWatching(_channel);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await MessageService.loadRecipients(widget.item.messageId);
      // New replies first, then not read, then read
      int rank(RecipientStatus r) => r.newReplyForSender ? 0 : (!r.isRead ? 1 : 2);
      list.sort((a, b) {
        final c = rank(a).compareTo(rank(b));
        return c != 0 ? c : a.name.compareTo(b.name);
      });
      if (!mounted) return;
      setState(() {
        _recipients = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('Load recipients error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load delivery status. Check your internet connection.';
        });
      }
    }
  }

  void _openConversation(RecipientStatus r) {
    final item = widget.item;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessageThreadPage(
          rowId: r.rowId,
          title: item.title,
          body: item.body,
          priority: item.priority,
          sentAt: item.sentAt,
          senderName: me?.fullName ?? 'You',
          otherPartyName: r.name,
          viewerIsSender: true,
          readAt: r.readAt,
        ),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final read = _recipients.where((r) => r.isRead).length;
    final replied = _recipients.where((r) => r.replyCount > 0).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text("Sent Message"),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(14),
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navy)),
                    Text("To: ${item.toLabel}  |  ${MessageService.timeAgo(item.sentAt)}",
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    const Divider(),
                    Text(item.body),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _countBox("Delivered", "${_recipients.length}", Colors.indigo),
                const SizedBox(width: 8),
                _countBox("Read", "$read", Colors.blue),
                const SizedBox(width: 8),
                _countBox("Not read", "${_recipients.length - read}", Colors.orange.shade800),
                const SizedBox(width: 8),
                _countBox("Replied", "$replied", Colors.green.shade700),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center)
            else if (_recipients.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  "This message was not delivered to anyone (no one matched who it was sent to).",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ..._recipients.map((r) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: r.newReplyForSender ? Colors.green.shade300 : Colors.grey.shade200),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _navy.withOpacity(0.08),
                        child: Text(r.name.isEmpty ? '?' : r.name[0], style: const TextStyle(color: _navy)),
                      ),
                      title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Row(
                        children: [
                          Icon(r.isRead ? Icons.done_all : Icons.done, size: 14, color: r.isRead ? Colors.blue : Colors.grey),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              r.isRead ? "Read ${MessageService.timeAgo(r.readAt)}" : "Not read yet",
                              style: TextStyle(fontSize: 12, color: r.isRead ? Colors.blue : Colors.grey),
                            ),
                          ),
                          if (r.replyCount > 0) ...[
                            const SizedBox(width: 8),
                            Text("${r.replyCount} repl${r.replyCount == 1 ? 'y' : 'ies'}",
                                style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ],
                      ),
                      trailing: r.newReplyForSender
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                              child: Text("New reply",
                                  style: TextStyle(color: Colors.green.shade800, fontSize: 11, fontWeight: FontWeight.bold)),
                            )
                          : const Icon(Icons.chat_bubble_outline, size: 18, color: Colors.grey),
                      onTap: () => _openConversation(r),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _countBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// INBOX LIST (used by the Messages page and the student dashboard)
// =====================================================================
class InboxList extends StatelessWidget {
  final InboxController controller;
  final String emptyText;

  const InboxList({super.key, required this.controller, required this.emptyText});

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
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(controller.error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                ),
              if (items.isNotEmpty && controller.unreadCount > 0)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: controller.markAllRead,
                    icon: const Icon(Icons.done_all, size: 18),
                    label: Text("Mark all read (${controller.unreadCount})"),
                  ),
                ),
              if (items.isEmpty && controller.error == null)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(child: Text(emptyText, style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center)),
                ),
              ...items.map((item) => _InboxTile(
                    item: item,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => MessageThreadPage.fromInbox(item)),
                    ).then((_) => controller.refresh()),
                  )),
            ],
          ),
        );
      },
    );
  }
}

class _InboxTile extends StatelessWidget {
  final InboxItem item;
  final VoidCallback onTap;
  const _InboxTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = item.isUnread;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: unread ? 2 : 0.5,
      color: unread ? const Color(0xFFEFF4FF) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: item.isImportant ? Colors.red.withOpacity(0.4) : Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: (item.senderRole == 'admin' ? Colors.indigo : _navy).withOpacity(0.1),
          child: Icon(item.senderRole == 'admin' ? Icons.campaign : Icons.mail,
              color: item.senderRole == 'admin' ? Colors.indigo : _navy, size: 20),
        ),
        title: Row(
          children: [
            if (unread)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
              ),
            Expanded(
              child: Text(item.title,
                  style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.body, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              "From: ${item.fromLabel}  |  ${MessageService.timeAgo(item.sentAt)}"
              "${item.replyCount > 0 ? '  |  ${item.replyCount} repl${item.replyCount == 1 ? 'y' : 'ies'}' : ''}",
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        trailing: item.newReplyFromSender
            ? const Text("New reply", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold))
            : item.isImportant
                ? const Text("Important", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold))
                : null,
        onTap: onTap,
      ),
    );
  }
}

/// A full-screen inbox (used by the student dashboard).
class InboxPage extends StatelessWidget {
  final InboxController controller;
  final String title;
  const InboxPage({super.key, required this.controller, this.title = "Messages"});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      appBar: AppBar(backgroundColor: _navy, foregroundColor: Colors.white, title: Text(title)),
      body: InboxList(controller: controller, emptyText: "No messages yet."),
    );
  }
}
