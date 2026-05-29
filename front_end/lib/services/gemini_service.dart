import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/reminder.dart';
import 'auth_service.dart';

class ZamResponse {
  final String message;
  final String? action;
  final ReminderIntent? reminder;
  final List<String> suggestions;
  final String? error;

  const ZamResponse({
    required this.message,
    this.action,
    this.reminder,
    this.suggestions = const [],
    this.error,
  });

  factory ZamResponse.error(String msg) =>
      ZamResponse(message: msg, error: msg);
}

class ReminderIntent {
  final String name;
  final String time;
  final String recurrence;
  final int? snoozeMinutes;
  final int? delayMinutes;

  const ReminderIntent({
    required this.name,
    required this.time,
    this.recurrence = 'none',
    this.snoozeMinutes,
    this.delayMinutes,
  });

  factory ReminderIntent.fromJson(Map<String, dynamic> json) {
    final rawSnooze = json['snoozeMinutes'];
    return ReminderIntent(
      name: json['name'] as String? ?? 'Medicine',
      time: json['time'] as String? ?? '08:00',
      recurrence: json['recurrence'] as String? ?? 'none',
      snoozeMinutes: rawSnooze is num ? rawSnooze.round() : null,
      delayMinutes: json['delayMinutes'] is num
          ? (json['delayMinutes'] as num).round()
          : null,
    );
  }
}

class GeminiService {
  static String get _backendUrl {
    final raw = dotenv.env['BACKEND_URL']?.trim() ?? '';
    if (raw.isEmpty || raw == '*') return '';
    if (raw.endsWith('/')) return raw.substring(0, raw.length - 1);
    return raw;
  }

  // ── Rate limiting: per-instance cooldown ───────────────────────────────────
  // Minimum gap between requests — prevents bursting even if the user types fast
  static const Duration _minRequestGap = Duration(seconds: 3);
  DateTime? _lastRequestTime;

  // Queue: only ONE request in flight at a time
  bool _requestInFlight = false;
  final List<_QueuedRequest> _queue = [];

  // Gemini calls must go through backend so API key is never inside APK.

  // ── Public chat method ─────────────────────────────────────────────────────

  Future<ZamResponse> chat({
    required String userMessage,
    required List<Reminder> reminders,
  }) {
    if (_requestInFlight || _queue.isNotEmpty) {
      return Future.value(
        ZamResponse.error(
            "I'm still working on your last message. Try again in a moment."),
      );
    }

    final completer = Completer<ZamResponse>();
    _queue.add(
      _QueuedRequest(
        userMessage: userMessage,
        reminders: List.from(reminders),
        completer: completer,
      ),
    );
    _processQueue();
    return completer.future;
  }

  void clearHistory() {}

  // ── Queue ──────────────────────────────────────────────────────────────────

  void _processQueue() {
    if (_requestInFlight || _queue.isEmpty) return;
    _requestInFlight = true;

    final req = _queue.removeAt(0);

    // Enforce minimum gap between requests
    final now = DateTime.now();
    final gap = _lastRequestTime == null
        ? Duration.zero
        : now.difference(_lastRequestTime!);
    final wait = gap < _minRequestGap ? _minRequestGap - gap : Duration.zero;

    Future.delayed(wait, () => _executeWithRetry(req)).then((res) {
      req.completer.complete(res);
    }).catchError((e) {
      req.completer.complete(ZamResponse.error("Unexpected error: $e"));
    }).whenComplete(() {
      _requestInFlight = false;
      if (_queue.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 200), _processQueue);
      }
    });
  }

  // ── One request only ───────────────────────────────────────────────────────

  Future<ZamResponse> _executeWithRetry(_QueuedRequest req) async {
    return _doRequest(req);
  }

  // ── Single HTTP request ────────────────────────────────────────────────────

  Future<ZamResponse> _doRequest(_QueuedRequest req) async {
    _lastRequestTime = DateTime.now();
    if (_backendUrl.isEmpty) {
      return ZamResponse.error(
        'Backend is not configured. Set BACKEND_URL in front_end/.env.',
      );
    }
    return _doBackendRequest(req);
  }

  // ── Trim history ───────────────────────────────────────────────────────────

  Future<ZamResponse> _doBackendRequest(_QueuedRequest req) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      final token = await AuthService.getIdToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http
          .post(
            Uri.parse('$_backendUrl/api/chat'),
            headers: headers,
            body: jsonEncode({
              'userMessage': req.userMessage,
              'reminders': req.reminders.map((r) => r.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      final parsed = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ZamResponse.error(
          parsed['message'] as String? ??
              'Backend error ${response.statusCode}',
        );
      }
      return _parseZamResponse(parsed);
    } on TimeoutException {
      return ZamResponse.error('Backend timed out. Check your connection.');
    } on SocketException {
      return ZamResponse.error(
        "You're offline right now. Check your internet connection, then try again.",
      );
    } catch (e) {
      debugPrint('Backend chat error: $e');
      return ZamResponse.error(
        'Could not reach the backend. Check your connection.',
      );
    }
  }

  ZamResponse _parseZamResponse(
    Map<String, dynamic> parsed, {
    String fallbackMessage = '',
  }) {
    ReminderIntent? intent;
    if (parsed['reminder'] != null) {
      intent = ReminderIntent.fromJson(
        parsed['reminder'] as Map<String, dynamic>,
      );
    }

    final rawSuggestions = parsed['suggestions'];
    final suggestions =
        rawSuggestions is List ? rawSuggestions.cast<String>() : <String>[];

    return ZamResponse(
      message: parsed['message'] as String? ?? fallbackMessage,
      action: parsed['action'] as String?,
      reminder: intent,
      suggestions: suggestions,
      error: parsed['error'] as String?,
    );
  }
}

class _QueuedRequest {
  final String userMessage;
  final List<Reminder> reminders;
  final Completer<ZamResponse> completer;

  _QueuedRequest({
    required this.userMessage,
    required this.reminders,
    required this.completer,
  });
}
