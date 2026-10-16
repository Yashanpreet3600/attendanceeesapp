import 'package:flutter/material.dart';
import 'app_session.dart';

/// Lets the logged-in person change their password.
/// [firstLogin] = true right after logging in with a starting/reset
/// password: the dialog explains why and offers "Later".
Future<void> showChangePasswordDialog(BuildContext context, {bool firstLogin = false}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !firstLogin,
    builder: (_) => _ChangePasswordDialog(firstLogin: firstLogin),
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  final bool firstLogin;
  const _ChangePasswordDialog({required this.firstLogin});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final TextEditingController _oldCtrl = TextEditingController();
  final TextEditingController _newCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final oldPw = _oldCtrl.text;
    final newPw = _newCtrl.text;
    if (oldPw.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }
    if (newPw.length < 6) {
      setState(() => _error = 'The new password must have at least 6 characters.');
      return;
    }
    if (newPw != _confirmCtrl.text) {
      setState(() => _error = 'The two new passwords are not the same.');
      return;
    }
    if (newPw == oldPw) {
      setState(() => _error = 'Choose a password different from the current one.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final error = await AppSession.changePassword(oldPw, newPw);
      if (!mounted) return;
      if (error != null) {
        setState(() {
          _busy = false;
          _error = error;
        });
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Password changed.'), backgroundColor: Colors.green));
    } catch (e) {
      debugPrint('Change password error: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not change the password. Check your internet connection and try again.';
        });
      }
    }
  }

  InputDecoration _deco(String label) => InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: IconButton(
          icon: Icon(_hide ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _hide = !_hide),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: const Text("Change Password"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.firstLogin)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(8)),
                child: const Text(
                  "You logged in with a starting password. Please choose your own password now so no one else can use your account.",
                  style: TextStyle(fontSize: 13),
                ),
              ),
            TextField(controller: _oldCtrl, obscureText: _hide, enabled: !_busy, decoration: _deco("Current password")),
            const SizedBox(height: 10),
            TextField(controller: _newCtrl, obscureText: _hide, enabled: !_busy, decoration: _deco("New password (6+ characters)")),
            const SizedBox(height: 10),
            TextField(controller: _confirmCtrl, obscureText: _hide, enabled: !_busy, decoration: _deco("New password again")),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(widget.firstLogin ? "Later" : "Cancel"),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text("Change Password"),
        ),
      ],
    );
  }
}
