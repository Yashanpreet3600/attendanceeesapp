import 'package:flutter/material.dart';
import 'leave_service.dart';

/// Shows a leave request's photo (medical certificate). Pinch to zoom.
Future<void> showLeaveAttachment(BuildContext context, String path) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(
              children: [
                const Expanded(child: Text("Attached Photo", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          Flexible(
            child: FutureBuilder<String>(
              future: LeaveService.attachmentUrl(path),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator());
                }
                if (snap.hasError || snap.data == null) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text("Could not open the photo. Check your internet connection.",
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.red)),
                  );
                }
                return InteractiveViewer(
                  maxScale: 5,
                  child: Image.network(
                    snap.data!,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) => progress == null
                        ? child
                        : const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()),
                    errorBuilder: (context, error, stack) => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text("Could not load the photo.", style: TextStyle(color: Colors.red)),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

/// Small "View attachment" button for leave cards.
class LeaveAttachmentButton extends StatelessWidget {
  final String path;
  const LeaveAttachmentButton({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => showLeaveAttachment(context, path),
      icon: const Icon(Icons.image, size: 18),
      label: const Text("View attachment"),
      style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
    );
  }
}
