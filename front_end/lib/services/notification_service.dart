import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../main.dart';

class NotificationService {
  static const String _channelId = 'zam_medicine_channel';

  static Future<bool> scheduleReminder({
    required int id,
    required String medicineName,
    required DateTime time,
    String recurrence = 'none',
  }) async {
    try {
      final tzTime = tz.TZDateTime.from(time, tz.local);
      if (tzTime.isBefore(tz.TZDateTime.now(tz.local))) {
        debugPrint('NotificationService: time is in the past, skipping');
        return false;
      }

      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            _channelId,
            'Medicine Reminders',
            channelDescription: 'Reminders to take your medicine on time',
            importance: Importance.max,
            priority: Priority.high,
            enableVibration: true,
            playSound: true,
            ticker: 'Time for $medicineName',
            styleInformation: BigTextStyleInformation(
              'Time to take your $medicineName 💊 Stay healthy!',
              contentTitle: '⏰ Medicine Reminder — Zam',
              summaryText: 'Zam',
            ),
          );

      final DateTimeComponents? matchDateTimeComponents = recurrence == 'daily'
          ? DateTimeComponents.time
          : recurrence == 'weekly'
          ? DateTimeComponents.dayOfWeekAndTime
          : null;

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        '⏰ Time for your medicine!',
        'Don\'t forget to take your $medicineName 💊',
        tzTime,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: medicineName,
      );

      debugPrint(
        'NotificationService: scheduled "$medicineName" at $time ($recurrence)',
      );
      return true;
    } catch (e) {
      debugPrint('NotificationService ERROR: $e');
      return false;
    }
  }

  static Future<void> cancelReminder(int id) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(id);
    } catch (e) {
      debugPrint('NotificationService cancel ERROR: $e');
    }
  }

  static Future<void> cancelAll() async {
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
    } catch (e) {
      debugPrint('NotificationService cancelAll ERROR: $e');
    }
  }

  static Future<void> showTestNotification() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _channelId,
          'Medicine Reminders',
          importance: Importance.max,
          priority: Priority.high,
        );
    await flutterLocalNotificationsPlugin.show(
      999,
      'Zam is working! ✅',
      'Notifications are set up correctly.',
      const NotificationDetails(android: androidDetails),
    );
  }
}
