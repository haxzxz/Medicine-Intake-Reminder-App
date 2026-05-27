import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
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
  static String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  static String get _model => dotenv.env['GEMINI_MODEL'] ?? 'gemini-2.0-flash';

  static String get _backendUrl {
    final raw = dotenv.env['BACKEND_URL']?.trim() ?? '';
    if (raw.endsWith('/')) return raw.substring(0, raw.length - 1);
    return raw;
  }

  static String get _url =>
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey';

  // ── Rate limiting: per-instance cooldown ───────────────────────────────────
  // Minimum gap between requests — prevents bursting even if the user types fast
  static const Duration _minRequestGap = Duration(seconds: 3);
  DateTime? _lastRequestTime;

  // Queue: only ONE request in flight at a time
  bool _requestInFlight = false;
  final List<_QueuedRequest> _queue = [];

  // Conversation history — trimmed to last 8 turns to save tokens
  final List<Map<String, dynamic>> _history = [];
  static const int _maxHistoryTurns = 8;

  // ── System prompt ──────────────────────────────────────────────────────────

  String _buildSystemPrompt(List<Reminder> reminders) {
    final now = DateTime.now();
    final timeFmt = DateFormat('h:mm a');
    final dateFmt = DateFormat('EEEE, MMMM d, yyyy');

    final activeReminders = reminders.isEmpty
        ? 'None'
        : reminders.map(
            (r) {
              final status = r.fired
                  ? 'taken/completed'
                  : r.isPast
                      ? 'due now'
                      : 'pending';
              return '- id ${r.id}: ${r.medicineName} at ${timeFmt.format(r.time)} (${r.timeUntilLabel}, status $status, repeats ${r.recurrence})';
            },
          ).join('\n');

    return '''You are Zam, a warm, smart, casual AI medicine reminder assistant.
Today is ${dateFmt.format(now)}, current time is ${timeFmt.format(now)}.

ACTIVE REMINDERS:
$activeReminders

IMPORTANT STATE RULE:
- ACTIVE REMINDERS is the source of truth. If it says None, tell the user they have no active reminders.
- Ignore older conversation messages that imply a reminder is still active when ACTIVE REMINDERS no longer lists it.
- Completed/taken/missed reminders are history, not active reminders.

YOUR CAPABILITIES:
1. SET REMINDERS — understand casual language: "pills 8ish", "meds tonite 9", "biogesic 7pm", "metformin daily at 8"
2. MANAGE REMINDERS — "what do I have set?", "clear everything", "delete vitamin reminder", "snooze biogesic 10 minutes"
3. HEALTH INFO — brief helpful tips (food interactions, storage, timing). Say "consult your doctor" for symptoms.
4. CONVERSATION MEMORY — remember everything said this session; handle follow-ups naturally

RESPONSE FORMAT — respond ONLY with valid JSON, no markdown, no backticks:
{
  "message": "warm brief reply, 2-3 sentences. Use \\n for newlines. Emoji ok.",
  "action": null,
  "reminder": null,
  "suggestions": ["chip 1", "chip 2", "chip 3"]
}

To set a reminder at a clock time:
{ "message": "...", "action": "set_reminder", "reminder": { "name": "Medicine Name", "time": "HH:MM", "recurrence": "none" }, "suggestions": [...] }

To set a relative reminder:
{ "message": "...", "action": "set_reminder", "reminder": { "name": "Medicine Name", "time": "00:00", "delayMinutes": 1, "recurrence": "none" }, "suggestions": [...] }

To set a recurring reminder, use recurrence "daily" or "weekly".

To delete one reminder by name:
{ "message": "...", "action": "delete_reminder", "reminder": { "name": "Medicine Name", "time": "00:00", "recurrence": "none" }, "suggestions": [...] }

To delete all:
{ "message": "...", "action": "delete_all", "reminder": null, "suggestions": [...] }

To snooze one reminder:
{ "message": "...", "action": "snooze_reminder", "reminder": { "name": "Medicine Name", "time": "00:00", "recurrence": "none", "snoozeMinutes": 10 }, "suggestions": [...] }

TIME RULES:
- For "in X minute(s)" or "after X minute(s)", ALWAYS use delayMinutes instead of rounding to HH:MM.
- "8ish" → 08:00 if morning context, 20:00 if evening context
- "tonight/evening/pm" → PM hours
- "morning" → 08:00, "noon/lunch" → 12:00, "night/bedtime" → 21:00, "after dinner" → 19:00
- Bare 1-6 → assume PM. Bare 7-11 → prefer AM unless context says PM
- Always output 24-hour "HH:MM"
- When asked to check reminders, list only pending/due reminders as active. Do not call taken/completed reminders "set".

MEDICINE NAME RULES:
- Extract real name: "Biogesic", "Vitamin C", "Metformin"
- "my pills/meds" with no name → "Medicine"
- Capitalise correctly
- For delete/snooze, use the closest active reminder name from ACTIVE REMINDERS

RECURRENCE RULES:
- "every day", "daily", "each morning/night" → recurrence "daily"
- "weekly", "every week", "every Monday" → recurrence "weekly"
- Otherwise recurrence "none"
- Snooze defaults to 10 minutes if the user does not specify

PERSONALITY: casual, warm, brief. Don't repeat reminder details (the card shows them).''';
  }

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

  void clearHistory() => _history.clear();

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

    if (_backendUrl.isNotEmpty) {
      return _doBackendRequest(req);
    }

    if (_apiKey.isEmpty) {
      return ZamResponse.error(
        "Gemini isn't configured yet. Add GEMINI_API_KEY to the app's .env file.",
      );
    }

    _history.add({
      'role': 'user',
      'parts': [
        {'text': req.userMessage},
      ],
    });

    try {
      final response = await http
          .post(
            Uri.parse(_url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'system_instruction': {
                'parts': [
                  {'text': _buildSystemPrompt(req.reminders)},
                ],
              },
              'contents': _history,
              'generationConfig': {
                'temperature': 0.7,
                'maxOutputTokens': 500, // Keep short to save quota
                'responseMimeType': 'application/json',
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 429) {
        _history.removeLast();
        return ZamResponse.error(_quotaErrorMessage(response.body));
      }
      if (response.statusCode == 400) {
        _history.removeLast();
        final err = jsonDecode(response.body);
        final msg = err['error']?['message'] as String? ?? 'Bad request';
        return ZamResponse.error("Gemini error: $msg");
      }
      if (response.statusCode == 403) {
        _history.removeLast();
        return ZamResponse.error(_apiKeyErrorMessage(response.body));
      }
      if (response.statusCode != 200) {
        _history.removeLast();
        return ZamResponse.error("Gemini error ${response.statusCode}");
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = body['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        _history.removeLast();
        return ZamResponse.error("Empty response. Try again.");
      }

      final rawText =
          candidates[0]['content']?['parts']?[0]?['text'] as String? ?? '';

      _history.add({
        'role': 'model',
        'parts': [
          {'text': rawText},
        ],
      });
      _trimHistory();

      try {
        final clean = rawText.replaceAll(RegExp(r'```json|```'), '').trim();
        final parsed = jsonDecode(clean) as Map<String, dynamic>;

        return _parseZamResponse(parsed, fallbackMessage: rawText);
      } catch (e) {
        debugPrint('JSON parse error: $e\nRaw: $rawText');
        return ZamResponse(message: rawText);
      }
    } on TimeoutException {
      _history.removeLast();
      return ZamResponse.error("Request timed out. Check your internet.");
    } catch (e) {
      _history.removeLast();
      debugPrint('Gemini error: $e');
      return ZamResponse.error(
        "Could not reach Gemini. Check your connection.",
      );
    }
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

  void _trimHistory() {
    final maxMessages = _maxHistoryTurns * 2;
    if (_history.length > maxMessages) {
      final excess = _history.length - maxMessages;
      final removeCount = excess.isEven ? excess : excess + 1;
      _history.removeRange(0, removeCount.clamp(0, _history.length));
    }
  }

  String _apiKeyErrorMessage(String responseBody) {
    try {
      final err = jsonDecode(responseBody) as Map<String, dynamic>;
      final message = err['error']?['message'] as String? ?? '';
      if (message.contains('Android client application <empty>')) {
        return "Gemini rejected the API key because it is restricted to Android apps. In Google Cloud, set the key's application restriction to None, or route Gemini calls through a backend.";
      }
      if (message.toLowerCase().contains('api key not valid')) {
        return 'Gemini rejected the API key. Check that GEMINI_API_KEY is current and copied into front_end/.env.';
      }
      if (message.isNotEmpty) {
        return 'Gemini API key error: $message';
      }
    } catch (_) {}
    return 'Gemini API key issue. Check the key restrictions in Google Cloud.';
  }

  String _quotaErrorMessage(String responseBody) {
    try {
      final err = jsonDecode(responseBody) as Map<String, dynamic>;
      final message = err['error']?['message'] as String? ?? '';
      final retryMatch =
          RegExp(r'Please retry in ([^.\n]+)').firstMatch(message);
      final retry =
          retryMatch == null ? '' : ' Try again in ${retryMatch.group(1)}.';

      if (message.contains('limit: 0')) {
        return "Gemini says this API key has no free quota available for $_model right now.$retry You can switch GEMINI_MODEL to gemini-flash-lite-latest or enable billing/quota in Google AI Studio.";
      }
      if (message.isNotEmpty) {
        return 'Gemini quota limit reached.$retry';
      }
    } catch (_) {}
    return 'Gemini quota limit reached. Please wait a bit and try again.';
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
