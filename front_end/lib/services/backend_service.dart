import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/reminder.dart';
import '../models/reminder_log.dart';
import 'auth_service.dart';

class BackendService {
  static String get _baseUrl {
    final raw = dotenv.env['BACKEND_URL']?.trim() ?? '';
    if (raw.isEmpty || raw == '*') return '';
    if (raw.endsWith('/')) return raw.substring(0, raw.length - 1);
    return raw;
  }

  static bool get isConfigured => _baseUrl.isNotEmpty;

  static Future<Map<String, String>> _headers() async {
    final headers = {'Content-Type': 'application/json'};
    final token = await AuthService.getIdToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static Future<bool> healthCheck() async {
    if (!isConfigured) return false;
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/api/health'))
          .timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Backend health failed: $e');
      return false;
    }
  }

  static Future<List<Reminder>> loadReminders() async {
    if (!isConfigured) return [];
    try {
      final res = await http
          .get(
            Uri.parse('$_baseUrl/api/reminders'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final items = body['reminders'] as List? ?? [];
      return items
          .map((item) => Reminder.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Backend load reminders failed: $e');
      return [];
    }
  }

  static Future<BackendSyncResult> syncReminders(
    List<Reminder> reminders,
  ) async {
    if (!isConfigured) return const BackendSyncResult.skipped();
    final failures = <int, String>{};

    await Future.wait(
      reminders.map((reminder) async {
        try {
          final synced = await upsertReminder(reminder);
          if (!synced) {
            failures[reminder.id] = 'Request failed';
          }
        } catch (e) {
          failures[reminder.id] = e.toString();
        }
      }),
    );

    if (failures.isNotEmpty) {
      debugPrint('Backend sync failed for reminder ids: ${failures.keys}');
    }
    return BackendSyncResult(
      attempted: reminders.length,
      failedIds: failures.keys.toList(),
      errorsById: failures,
    );
  }

  static Future<bool> upsertReminder(Reminder reminder) async {
    if (!isConfigured) return false;
    try {
      final res = await http
          .put(
            Uri.parse('$_baseUrl/api/reminders/${reminder.id}'),
            headers: await _headers(),
            body: jsonEncode(reminder.toJson()),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint(
          'Backend upsert reminder failed: ${res.statusCode} ${res.body}',
        );
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Backend upsert reminder failed: $e');
      return false;
    }
  }

  static Future<void> deleteReminder(int id) async {
    if (!isConfigured) return;
    try {
      await http
          .delete(
            Uri.parse('$_baseUrl/api/reminders/$id'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Backend delete reminder failed: $e');
    }
  }

  static Future<void> deleteAllReminders() async {
    if (!isConfigured) return;
    try {
      await http
          .delete(
            Uri.parse('$_baseUrl/api/reminders'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Backend delete all reminders failed: $e');
    }
  }

  static Future<void> appendLog(ReminderLog log) async {
    if (!isConfigured) return;
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/api/reminder-logs'),
            headers: await _headers(),
            body: jsonEncode(log.toJson()),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Backend append log failed: $e');
    }
  }

  static Future<List<ReminderLog>> loadLogs() async {
    if (!isConfigured) return [];
    try {
      final res = await http
          .get(
            Uri.parse('$_baseUrl/api/reminder-logs'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final items = body['logs'] as List? ?? [];
      return items
          .map((item) => ReminderLog.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Backend load logs failed: $e');
      return [];
    }
  }

  static Future<void> deleteAllLogs() async {
    if (!isConfigured) return;
    try {
      await http
          .delete(
            Uri.parse('$_baseUrl/api/reminder-logs'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Backend delete logs failed: $e');
    }
  }
}

class BackendSyncResult {
  final int attempted;
  final List<int> failedIds;
  final Map<int, String> errorsById;
  final bool skipped;

  const BackendSyncResult({
    required this.attempted,
    required this.failedIds,
    required this.errorsById,
    this.skipped = false,
  });

  const BackendSyncResult.skipped()
      : attempted = 0,
        failedIds = const [],
        errorsById = const {},
        skipped = true;

  bool get success => failedIds.isEmpty;
}
