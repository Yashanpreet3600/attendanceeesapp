import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shows notifications in the phone's notification bar (Android).
///
/// They appear while the app is open or still running in the
/// background. For notifications when the app is fully closed, the app
/// needs Firebase Cloud Messaging (a later step).
///
/// On web (Chrome) this does nothing; in-app pop-ups still work.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _nextId = 1;

  static const AndroidNotificationDetails _android = AndroidNotificationDetails(
    'attendease_alerts',
    'Messages and leave',
    channelDescription: 'New messages, replies and leave updates',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Call once at app start. Asks for permission on Android 13+.
  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      // e.g. running on a platform that isn't set up (iOS/desktop)
      debugPrint('Notifications not available: $e');
    }
  }

  static Future<void> show(String title, String body) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: _android),
      );
    } catch (e) {
      debugPrint('Show notification error: $e');
    }
  }
}
