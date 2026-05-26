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

  static Future<void> syncReminders(List<Reminder> reminders) async {
    if (!isConfigured) return;
    for (final reminder in reminders) {
      unawaited(upsertReminder(reminder));
    }
  }

  static Future<void> upsertReminder(Reminder reminder) async {
    if (!isConfigured) return;
    try {
      await http
          .put(
            Uri.parse('$_baseUrl/api/reminders/${reminder.id}'),
            headers: await _headers(),
            body: jsonEncode(reminder.toJson()),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Backend upsert reminder failed: $e');
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
}
