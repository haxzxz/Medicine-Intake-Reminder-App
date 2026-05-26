import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reminder.dart';
import '../models/reminder_log.dart';
import 'auth_service.dart';

class StorageService {
  static const String _remindersKey = 'zam_reminders_v2';
  static const String _logsKey = 'zam_reminder_logs_v1';

  static String get _userScope {
    final user = AuthService.currentUser;
    return user?.uid ?? user?.email ?? 'signed_out';
  }

  static String _scopedKey(String key) => '${key}_$_userScope';

  // ── Reminders ──────────────────────────────────────────────────────────────

  static Future<List<Reminder>> loadReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_scopedKey(_remindersKey));
      if (raw == null) return [];
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded
          .map((e) => Reminder.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveReminders(List<Reminder> reminders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _scopedKey(_remindersKey),
        jsonEncode(reminders.map((r) => r.toJson()).toList()),
      );
    } catch (_) {}
  }

  static Future<void> clearReminders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scopedKey(_remindersKey));
  }

  // ── Reminder Logs ──────────────────────────────────────────────────────────

  static Future<List<ReminderLog>> loadLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_scopedKey(_logsKey));
      if (raw == null) return [];
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded
          .map((e) => ReminderLog.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> appendLog(ReminderLog log) async {
    final logs = await loadLogs();
    logs.add(log);
    // Keep max 200 entries — oldest first, trim from front
    final trimmed = logs.length > 200 ? logs.sublist(logs.length - 200) : logs;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _scopedKey(_logsKey),
      jsonEncode(trimmed.map((l) => l.toJson()).toList()),
    );
  }

  static Future<void> clearLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scopedKey(_logsKey));
  }
}
