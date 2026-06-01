import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'dart:async';
import '../models/reminder.dart';
import '../models/reminder_log.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import '../services/gemini_service.dart';
import '../services/notification_service.dart';
import '../services/reminder_text_parser.dart';
import '../services/storage_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/reminder_card.dart';
import 'profile_screen.dart';
import 'reminder_log_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final SpeechToText _speech = SpeechToText();
  final GeminiService _gemini = GeminiService();
  late final AnimationController _micPulseCtrl;
  late final Animation<double> _micScale;

  final List<Map<String, dynamic>> _messages = [];
  final List<Reminder> _reminders = [];
  List<String> _suggestions = [];

  Timer? _countdownTimer;
  Timer? _voiceAutoSendTimer;
  Timer? _voiceRestartTimer;
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _isLoading = false;
  bool _disposed = false;
  bool _isHoldingMic = false;
  bool _isStoppingVoice = false;
  String _voiceFinalText = '';
  String _voicePartialText = '';
  String? _speechLocaleId;
  int _voiceSessionId = 0;
  DateTime? _lastSendTime;
  int _nextId = 1;
  int _selectedIndex = 0;
  int _logRefreshTick = 0;
  final Set<int> _pendingConfirmations = {};

  static const Duration _voiceListenWindow = Duration(minutes: 5);
  static const Duration _voicePauseWindow = Duration(seconds: 45);
  static const Duration _voiceRestartDelay = Duration(milliseconds: 1600);
  static const Duration _voiceAutoSendDelay = Duration(seconds: 8);

  static const List<String> _defaultChips = [
    'yo zam pills 8ish',
    'what meds do I have set?',
    'is it safe to take ibuprofen with food?',
    'remind me in 2 minutes',
  ];

  @override
  void initState() {
    super.initState();
    _micPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _micScale = Tween<double>(begin: 1, end: 1.18).animate(
      CurvedAnimation(parent: _micPulseCtrl, curve: Curves.easeInOut),
    );
    _init();
  }

  Future<void> _init() async {
    unawaited(_initSpeech());
    _startCountdown();
    final name = AuthService.displayName.split(' ').first;
    _addBotMessage(
      "Hey $name! 👋 I'm Zam, your AI medicine reminder assistant.\n\nTry: \"yo zam pills 8ish now\" or ask me anything about your meds!",
      suggestions: _defaultChips,
    );
    unawaited(_loadData());
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (e) {
          debugPrint('Speech error: ${e.errorMsg}');
          if (_isHoldingMic && !_isStoppingVoice && !_disposed) {
            _restartListeningSoon();
          }
        },
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            if (_isHoldingMic && !_isStoppingVoice) {
              _restartListeningSoon();
            } else {
              _setListening(false);
            }
          }
        },
      );
      if (_speechAvailable) {
        final systemLocale = await _speech.systemLocale();
        _speechLocaleId = systemLocale?.localeId;
      }
    } catch (e) {
      debugPrint('Speech init: $e');
    }
  }

  Future<void> _loadData() async {
    unawaited(_loadLogsFromBackend());

    final saved = await StorageService.loadReminders();
    await _applyLoadedReminders(saved, syncAfter: false);

    final remote = await BackendService.loadReminders();
    if (remote.isEmpty) {
      unawaited(_syncRemindersToBackend());
      return;
    }

    final byId = {for (final reminder in saved) reminder.id: reminder};
    for (final reminder in remote) {
      byId[reminder.id] = reminder;
    }
    await _applyLoadedReminders(byId.values.toList());
  }

  Future<void> _loadLogsFromBackend() async {
    final remoteLogs = await BackendService.loadLogs();
    if (remoteLogs.isEmpty) return;
    await StorageService.saveLogs(remoteLogs);
    _safeSetState(() => _logRefreshTick++);
  }

  Future<void> _applyLoadedReminders(
    List<Reminder> loaded, {
    bool syncAfter = true,
  }) async {
    final active = <Reminder>[];

    for (final r in loaded) {
      if (r.isPast && !r.fired) {
        await _logReminder(r, 'missed');
        if (r.isRecurring) {
          final next = r.nextOccurrence();
          active.add(next);
          await _scheduleReminder(next);
        }
      } else if (r.isPast && r.fired) {
        if (r.isRecurring) {
          final next = r.nextOccurrence();
          active.add(next);
          await _scheduleReminder(next);
        }
      } else {
        active.add(r);
      }
    }

    _safeSetState(() {
      _reminders.clear();
      _reminders.addAll(active);
      if (_reminders.isNotEmpty) {
        _nextId =
            _reminders.map((r) => r.id).reduce((a, b) => a > b ? a : b) + 1;
      }
    });
    await StorageService.saveReminders(_reminders);
    if (syncAfter) unawaited(_syncRemindersToBackend());
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      for (var i = 0; i < _reminders.length; i++) {
        final r = _reminders[i];
        if (!r.fired &&
            r.time.isBefore(DateTime.now()) &&
            !_pendingConfirmations.contains(r.id)) {
          _pendingConfirmations.add(r.id);
          unawaited(_confirmDueReminder(r));
        }
      }
      _safeSetState(() {});
    });
  }

  void _safeSetState(VoidCallback fn) {
    if (!_disposed && mounted) setState(fn);
  }

  void _addBotMessage(
    String text, {
    Reminder? reminder,
    List<String>? suggestions,
  }) {
    _safeSetState(() {
      _messages.add({'role': 'bot', 'text': text, 'reminder': reminder});
      if (suggestions != null) _suggestions = suggestions;
    });
    _scrollToBottom();
  }

  void _addUserMessage(String text) {
    _safeSetState(() {
      _messages.add({'role': 'user', 'text': text});
      _suggestions = [];
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send([String? override, bool stopVoice = true]) async {
    HapticFeedback.selectionClick();
    // Debounce: prevent double-fires from voice + keyboard
    final now = DateTime.now();
    if (_lastSendTime != null &&
        now.difference(_lastSendTime!).inMilliseconds < 800) {
      return;
    }
    _lastSendTime = now;

    if (stopVoice && (_isListening || _isHoldingMic)) {
      await _stopListening(send: false);
    }

    final text = (override ?? _inputCtrl.text).trim();
    if (text.isEmpty || _isLoading) return;
    _inputCtrl.clear();

    _addUserMessage(text);

    if (_isAllergicReactionQuestion(text)) {
      _addBotMessage(_allergySafetyResponse());
      return;
    }

    if (_isSymptomMedicationQuestion(text)) {
      _addBotMessage(_symptomMedicationSafetyResponse());
      return;
    }

    if (_isUnrelatedQuestion(text)) {
      _addBotMessage(
        "I'm here for medicine information, medicine intakes, and medicine reminders only. I can help you set a dose reminder or answer a medicine-related question.",
        suggestions: const [
          'set medicine reminder',
          'what meds do I have set?',
          'medicine safety question',
        ],
      );
      return;
    }

    final quickAbsoluteReminder = _quickAbsoluteReminderIntent(text);
    if (quickAbsoluteReminder != null) {
      await _createReminderFromIntent(quickAbsoluteReminder, text);
      return;
    }

    final quickRelativeReminder = _quickRelativeReminderIntent(text);
    if (quickRelativeReminder != null) {
      await _createReminderFromIntent(quickRelativeReminder);
      return;
    }

    if (_isReminderStatusQuestion(text)) {
      _addBotMessage(_activeReminderSummary());
      return;
    }

    _safeSetState(() => _isLoading = true);

    // Key comes from .env via GeminiService — no UI dialog needed
    final res = await _gemini.chat(userMessage: text, reminders: _reminders);

    Reminder? newReminder;
    if (res.action == 'set_reminder' && res.reminder != null) {
      newReminder = await _createReminderFromIntent(res.reminder!, text);
    } else if (res.action == 'delete_reminder') {
      final reminder = _findReminderByName(res.reminder?.name);
      if (reminder == null) {
        _addBotMessage(
          "I couldn't find that reminder. Want me to list what's active?",
        );
      } else {
        await _deleteReminderInternal(reminder);
      }
    } else if (res.action == 'snooze_reminder') {
      final reminder = _findReminderByName(res.reminder?.name);
      if (reminder == null) {
        _addBotMessage(
          "I couldn't find a reminder to snooze. Which medicine should I move?",
        );
      } else {
        await _snoozeReminder(
          reminder,
          minutes: res.reminder?.snoozeMinutes ?? 10,
        );
      }
    } else if (res.action == 'delete_all') {
      // Log deleted reminders before clearing
      for (final r in _reminders) {
        await _logReminder(r, 'deleted');
      }
      await NotificationService.cancelAll();
      _reminders.clear();
      await StorageService.clearReminders();
      unawaited(BackendService.deleteAllReminders());
      _gemini.clearHistory();
    }

    _safeSetState(() => _isLoading = false);
    _addBotMessage(
      res.message,
      reminder: newReminder,
      suggestions: res.suggestions.isNotEmpty ? res.suggestions : null,
    );
  }

  DateTime _parseReminderTime(ReminderIntent intent, String sourceText) {
    final explicitTime = _clockTimeFromText(sourceText);
    if (explicitTime != null) return explicitTime;

    final delay = intent.delayMinutes ?? _relativeDelayFromText(sourceText);
    if (delay != null && delay > 0) {
      return DateTime.now().add(Duration(minutes: delay));
    }
    return _parseTime(intent.time);
  }

  Future<Reminder> _createReminderFromIntent(
    ReminderIntent intent, [
    String sourceText = '',
  ]) async {
    final time = _parseReminderTime(intent, sourceText);
    final medicineName = _cleanMedicineName(intent.name, sourceText);
    final reminder = Reminder(
      id: _nextId++,
      medicineName: medicineName,
      time: time,
      recurrence: _normaliseRecurrence(intent.recurrence),
    );
    _reminders.add(reminder);
    await _scheduleReminder(reminder);
    await StorageService.saveReminders(_reminders);
    unawaited(_upsertReminderToBackend(reminder));
    _gemini.clearHistory();
    _addBotMessage(
      'Got it! I set ${reminder.medicineName} for ${reminder.timeUntilLabel}.',
      reminder: reminder,
    );
    return reminder;
  }

  ReminderIntent? _quickAbsoluteReminderIntent(String text) {
    final time = _clockTimeFromText(text);
    if (time == null) return null;

    final normalized = text.toLowerCase();
    final looksLikeReminder = RegExp(
      r'\b(remind|reminder|take|medicine|meds|pill|pills|dose|drink)\b',
    ).hasMatch(normalized);
    if (!looksLikeReminder) return null;

    return ReminderIntent(
      name: _medicineNameFromClockText(text),
      time:
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
      recurrence: 'none',
    );
  }

  ReminderIntent? _quickRelativeReminderIntent(String text) {
    final delay = _relativeDelayFromText(text);
    if (delay == null || delay <= 0) return null;

    final normalized = text.toLowerCase();
    final looksLikeReminder = RegExp(
      r'\b(remind|reminder|take|medicine|meds|pill|pills|dose)\b',
    ).hasMatch(normalized);
    if (!looksLikeReminder) return null;

    final name = _medicineNameFromRelativeText(text);
    return ReminderIntent(
      name: name,
      time: '00:00',
      delayMinutes: delay,
      recurrence: 'none',
    );
  }

  String _medicineNameFromRelativeText(String text) {
    return ReminderTextParser.cleanMedicineName(text, text);
  }

  String _medicineNameFromClockText(String text) {
    return ReminderTextParser.medicineNameFromClockText(text);
  }

  String _cleanMedicineName(String rawName, [String sourceText = '']) {
    return ReminderTextParser.cleanMedicineName(rawName, sourceText);
  }

  bool _isReminderStatusQuestion(String text) {
    return ReminderTextParser.isReminderStatusQuestion(text);
  }

  bool _isUnrelatedQuestion(String text) {
    final normalized = text.toLowerCase().trim();
    final medicineWords = RegExp(
      r'\b(med|meds|medicine|medicines|pill|pills|dose|dosage|drug|drugs|tablet|capsule|remind|reminder|take|taken|snooze|delete|allergy|biogesic|paracetamol|ibuprofen|antibiotic|vitamin|prescription)\b',
    );
    if (medicineWords.hasMatch(normalized)) return false;

    return RegExp(
      r'\b(code|coding|program|sports|basketball|movie|music|joke|weather|travel|recipe|homework|math|finance|stock|crypto|politics|news|game|gaming)\b',
    ).hasMatch(normalized);
  }

  bool _isAllergicReactionQuestion(String text) {
    return ReminderTextParser.isAllergicReactionQuestion(text);
  }

  bool _isSymptomMedicationQuestion(String text) {
    return ReminderTextParser.isSymptomMedicationQuestion(text);
  }

  String _allergySafetyResponse() {
    return ReminderTextParser.allergySafetyResponse();
  }

  String _symptomMedicationSafetyResponse() {
    return ReminderTextParser.symptomMedicationSafetyResponse();
  }

  String _activeReminderSummary() {
    final active = _reminders.where((r) => !r.fired).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    if (active.isEmpty) {
      return "You don't have any active reminders right now. Completed or missed medicine intakes are in your reminder history.";
    }

    final fmt = DateFormat('h:mm a');
    final lines = active.map((r) {
      final status = r.isPast ? 'due now' : r.timeUntilLabel;
      final recurrence = r.isRecurring ? ', ${r.recurrence}' : '';
      return '• ${r.medicineName} at ${fmt.format(r.time)} ($status$recurrence)';
    }).join('\n');
    return 'Here are your active reminders:\n$lines';
  }

  int? _relativeDelayFromText(String text) {
    final match = RegExp(
      r'\b(?:in|after|for)\s+(\d{1,3})\s*(?:m|min|mins|minute|minutes)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  DateTime? _clockTimeFromText(String text) {
    return ReminderTextParser.clockTimeFromText(text);
  }

  DateTime _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 8;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    var t = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
      h,
      m,
    );
    if (t.isBefore(DateTime.now().add(const Duration(seconds: 10)))) {
      t = t.add(const Duration(days: 1));
    }
    return t;
  }

  String _normaliseRecurrence(String recurrence) {
    final value = recurrence.toLowerCase().trim();
    if (value == 'daily' || value == 'weekly') return value;
    return 'none';
  }

  Future<void> _scheduleReminder(Reminder r) {
    return NotificationService.scheduleReminder(
      id: r.id,
      medicineName: r.medicineName,
      time: r.time,
      recurrence: r.recurrence,
    );
  }

  Future<void> _logReminder(Reminder r, String status) async {
    final log = ReminderLog(
      reminderId: r.id,
      medicineName: r.medicineName,
      scheduledTime: r.time,
      firedAt: DateTime.now(),
      status: status,
    );
    await StorageService.appendLog(log);
    unawaited(BackendService.appendLog(log));
  }

  Future<void> _confirmDueReminder(Reminder r) async {
    if (!mounted || _disposed) return;
    _addBotMessage("🔔 Time to take your ${r.medicineName}.");

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Medicine reminder'),
          content: Text('Did you take ${r.medicineName}?'),
          actions: [
            TextButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.pop(dialogContext, 'missed');
              },
              child: const Text('Missed'),
            ),
            TextButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                Navigator.pop(dialogContext, 'snooze');
              },
              child: const Text('Snooze 10 min'),
            ),
            FilledButton(
              onPressed: () {
                HapticFeedback.heavyImpact();
                Navigator.pop(dialogContext, 'taken');
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF534AB7),
              ),
              child: const Text('Taken'),
            ),
          ],
        );
      },
    );

    _pendingConfirmations.remove(r.id);
    final index = _reminders.indexWhere((item) => item.id == r.id);
    if (index == -1) return;

    if (action == 'snooze') {
      await _snoozeReminder(_reminders[index], minutes: 10);
      _gemini.clearHistory();
      _addBotMessage('Snoozed ${r.medicineName} for 10 minutes.');
      return;
    }

    final status = action == 'taken' ? 'fired' : 'missed';
    await _logReminder(_reminders[index], status);
    if (_reminders[index].isRecurring) {
      final next = _reminders[index].nextOccurrence();
      _safeSetState(() => _reminders[index] = next);
      await _scheduleReminder(next);
      unawaited(_upsertReminderToBackend(next));
    } else {
      final completed = _reminders[index];
      completed.fired = true;
      _safeSetState(() => _reminders.removeAt(index));
      unawaited(BackendService.deleteReminder(completed.id));
    }
    await StorageService.saveReminders(_reminders);
    unawaited(_syncRemindersToBackend());
    _gemini.clearHistory();
    _addBotMessage(
      action == 'taken'
          ? 'Logged ${r.medicineName} as taken.'
          : 'Logged ${r.medicineName} as missed.',
    );
  }

  Reminder? _findReminderByName(String? name) {
    if (_reminders.isEmpty) return null;
    final target = name?.toLowerCase().trim() ?? '';
    if (target.isEmpty && _reminders.length == 1) return _reminders.first;
    if (target.isEmpty) return null;

    for (final r in _reminders) {
      if (r.medicineName.toLowerCase() == target) return r;
    }
    for (final r in _reminders) {
      final med = r.medicineName.toLowerCase();
      if (med.contains(target) || target.contains(med)) return r;
    }
    return null;
  }

  Future<void> _snoozeReminder(Reminder r, {required int minutes}) async {
    final safeMinutes = minutes.clamp(1, 240).toInt();
    final next = r.copyWith(
      time: DateTime.now().add(Duration(minutes: safeMinutes)),
      recurrence: 'none',
      fired: false,
    );
    final index = _reminders.indexWhere((item) => item.id == r.id);
    if (index == -1) return;

    await _logReminder(r, 'snoozed');
    await NotificationService.cancelReminder(r.id);
    _safeSetState(() => _reminders[index] = next);
    await _scheduleReminder(next);
    await StorageService.saveReminders(_reminders);
    unawaited(_upsertReminderToBackend(next));
    _gemini.clearHistory();
  }

  void _setListening(bool value) {
    if (value == _isListening) return;
    _safeSetState(() => _isListening = value);
    if (value) {
      _micPulseCtrl.repeat(reverse: true);
    } else {
      _micPulseCtrl.stop();
      _micPulseCtrl.reset();
    }
  }

  Future<void> _startListening() async {
    HapticFeedback.mediumImpact();
    if (!_speechAvailable) {
      _addBotMessage(
        "Microphone isn't available. Check mic permissions in Settings.",
      );
      return;
    }
    if (_isListening) return;
    _voiceSessionId++;
    _isStoppingVoice = false;
    _isHoldingMic = true;
    _voiceFinalText = '';
    _voicePartialText = '';
    _voiceRestartTimer?.cancel();
    _setListening(true);
    await _listenForSpeechSegment(_voiceSessionId);
  }

  Future<void> _listenForSpeechSegment(int sessionId) async {
    if (!_speechAvailable ||
        !_isHoldingMic ||
        _disposed ||
        sessionId != _voiceSessionId) {
      return;
    }
    if (_speech.isListening) return;
    try {
      await _speech.listen(
        onResult: (result) {
          if (result.recognizedWords.isNotEmpty &&
              sessionId == _voiceSessionId) {
            _captureSpeechResult(result.recognizedWords, result.finalResult);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: _speechLocaleId ?? 'en_US',
          listenFor: _voiceListenWindow,
          pauseFor: _voicePauseWindow,
          partialResults: true,
          cancelOnError: false,
        ),
      );
    } catch (e) {
      debugPrint('Speech listen failed: $e');
      if (_isHoldingMic && !_isStoppingVoice && !_disposed) {
        _restartListeningSoon();
      }
    }
  }

  Future<void> _toggleVoiceInput() async {
    if (_isListening || _isHoldingMic) {
      await _stopListening(send: true);
    } else {
      await _startListening();
    }
  }

  void _restartListeningSoon() {
    _voiceRestartTimer?.cancel();
    final sessionId = _voiceSessionId;
    _voiceRestartTimer = Timer(_voiceRestartDelay, () {
      if (_isHoldingMic &&
          !_isStoppingVoice &&
          !_disposed &&
          !_speech.isListening &&
          sessionId == _voiceSessionId) {
        unawaited(_listenForSpeechSegment(sessionId));
      }
    });
  }

  Future<void> _stopListening({required bool send}) async {
    if (!_isListening && !_isHoldingMic) return;
    HapticFeedback.lightImpact();
    _voiceAutoSendTimer?.cancel();
    _voiceRestartTimer?.cancel();
    _voiceSessionId++;
    _isStoppingVoice = true;
    _isHoldingMic = false;
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('Speech stop failed: $e');
    }
    _setListening(false);
    final text = _mergedVoiceText().trim();
    _voiceFinalText = '';
    _voicePartialText = '';
    _isStoppingVoice = false;
    if (send && text.isNotEmpty) {
      await _send(text, false);
    }
  }

  void _captureSpeechResult(String words, bool isFinal) {
    final cleaned = words.trim();
    if (cleaned.isEmpty) return;
    if (isFinal) {
      _voiceFinalText = _mergeVoiceChunk(_voiceFinalText, cleaned);
      _voicePartialText = '';
    } else {
      _voicePartialText = cleaned;
    }
    _safeSetState(() {
      final merged = _mergedVoiceText();
      _inputCtrl.value = TextEditingValue(
        text: merged,
        selection: TextSelection.collapsed(offset: merged.length),
      );
    });
    _scheduleVoiceAutoSend();
  }

  void _scheduleVoiceAutoSend() {
    _voiceAutoSendTimer?.cancel();
    if (!_isHoldingMic || _mergedVoiceText().trim().isEmpty) return;
    _voiceAutoSendTimer = Timer(_voiceAutoSendDelay, () {
      if (_isHoldingMic && !_disposed && _mergedVoiceText().trim().isNotEmpty) {
        unawaited(_stopListening(send: true));
      }
    });
  }

  String _mergedVoiceText() {
    if (_voicePartialText.isEmpty) return _voiceFinalText.trim();
    if (_voiceFinalText.isEmpty) return _voicePartialText.trim();
    final finalLower = _voiceFinalText.toLowerCase();
    final partialLower = _voicePartialText.toLowerCase();
    if (finalLower.endsWith(partialLower)) return _voiceFinalText.trim();
    return _mergeVoiceChunk(_voiceFinalText, _voicePartialText).trim();
  }

  String _mergeVoiceChunk(String first, String second) {
    final a = first.trim();
    final b = second.trim();
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    final aLower = a.toLowerCase();
    final bLower = b.toLowerCase();
    if (aLower == bLower || aLower.endsWith(bLower)) return a;
    if (bLower.startsWith(aLower)) return b;

    final aWords = a.split(RegExp(r'\s+'));
    final bWords = b.split(RegExp(r'\s+'));
    final maxOverlap =
        aWords.length < bWords.length ? aWords.length : bWords.length;
    for (var i = maxOverlap; i > 0; i--) {
      final tail = aWords.sublist(aWords.length - i).join(' ').toLowerCase();
      final head = bWords.sublist(0, i).join(' ').toLowerCase();
      if (tail == head) {
        return '${aWords.join(' ')} ${bWords.sublist(i).join(' ')}'.trim();
      }
    }
    return '$a $b';
  }

  Future<void> _deleteReminder(Reminder r) async {
    HapticFeedback.mediumImpact();
    await _deleteReminderInternal(r);
  }

  Future<void> _syncRemindersToBackend() async {
    final result = await BackendService.syncReminders(_reminders);
    if (!result.skipped && !result.success) {
      debugPrint(
        'Zam backend sync failed for ${result.failedIds.length}/${result.attempted} reminders.',
      );
    }
  }

  Future<void> _upsertReminderToBackend(Reminder reminder) async {
    final synced = await BackendService.upsertReminder(reminder);
    if (!synced && BackendService.isConfigured) {
      debugPrint('Zam backend upsert failed for reminder ${reminder.id}.');
    }
  }

  Future<void> _deleteReminderInternal(
    Reminder r, {
    bool showMessage = false,
  }) async {
    // Log as deleted before removing
    await _logReminder(r, 'deleted');
    await NotificationService.cancelReminder(r.id);
    _safeSetState(() => _reminders.remove(r));
    await StorageService.saveReminders(_reminders);
    unawaited(BackendService.deleteReminder(r.id));
    _gemini.clearHistory();
    if (showMessage) _addBotMessage('Deleted ${r.medicineName}.');
  }

  @override
  void dispose() {
    _disposed = true;
    _countdownTimer?.cancel();
    _voiceAutoSendTimer?.cancel();
    _voiceRestartTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _micPulseCtrl.dispose();
    _isHoldingMic = false;
    if (_isListening || _speech.isListening) _speech.stop();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: _buildAppBar(scheme, textTheme),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildChatTab(scheme),
          ReminderLogScreen(
            embedded: true,
            refreshToken: _logRefreshTick,
          ),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: _buildGlassNavigation(scheme),
    );
  }

  Widget _buildGlassNavigation(ColorScheme scheme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: NavigationBar(
                height: 66,
                backgroundColor: Colors.transparent,
                elevation: 0,
                indicatorColor: const Color(0xFF534AB7).withValues(alpha: 0.16),
                selectedIndex: _selectedIndex,
                onDestinationSelected: (index) {
                  HapticFeedback.selectionClick();
                  if (_isListening || _isHoldingMic) {
                    unawaited(_stopListening(send: false));
                  }
                  _safeSetState(() {
                    _selectedIndex = index;
                    if (index == 1) _logRefreshTick++;
                  });
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.chat_bubble_outline_rounded),
                    selectedIcon: Icon(Icons.chat_bubble_rounded),
                    label: 'Chat',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.history_rounded),
                    selectedIcon: Icon(Icons.history_rounded),
                    label: 'Logs',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatTab(ColorScheme scheme) {
    return Column(
      children: [
        if (_reminders.isNotEmpty) _buildRemindersStrip(scheme),
        Expanded(child: _buildMessages(scheme)),
        if (_isLoading) _buildTypingIndicator(scheme),
        if (_isListening) _buildListeningBanner(),
        if (_suggestions.isNotEmpty) _buildSuggestions(),
        _buildInputRow(scheme),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme scheme, TextTheme textTheme) {
    return AppBar(
      backgroundColor: scheme.surface.withValues(alpha: 0.88),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Row(
        children: [
          // Zam avatar
          Stack(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor:
                    const Color(0xFF534AB7).withValues(alpha: 0.15),
                child: const Text(
                  'Z',
                  style: TextStyle(
                    color: Color(0xFF534AB7),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D9E75),
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.surface, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Zam',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: const BoxDecoration(
                      color: Color(0xFF534AB7),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    'Powered by Gemini AI',
                    style: textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF534AB7),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
          height: 1,
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _buildRemindersStrip(ColorScheme scheme) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.82),
        border: Border(
          bottom:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Active reminders',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.45),
                    letterSpacing: 0.8,
                  ),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              itemCount: _reminders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (_, i) => _buildReminderChip(_reminders[i], scheme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderChip(Reminder r, ColorScheme scheme) {
    final isPast = r.isPast;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isPast ? Colors.orange.withValues(alpha: 0.08) : scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPast
              ? Colors.orange.withValues(alpha: 0.4)
              : scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPast ? Icons.check_circle_outline : Icons.medication,
            size: 16,
            color: isPast ? Colors.green : const Color(0xFF534AB7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.medicineName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${DateFormat('h:mm a').format(r.time)} · ${r.timeUntilLabel}${r.isRecurring ? ' · ${r.recurrence}' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isPast ? Colors.orange : const Color(0xFF534AB7),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _deleteReminder(r),
            child: Icon(
              Icons.close,
              size: 16,
              color: scheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(ColorScheme scheme) {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final msg = _messages[i];
        final isUser = msg['role'] == 'user';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              ChatBubble(text: msg['text'] as String, isUser: isUser),
              if (msg['reminder'] != null) ...[
                const SizedBox(height: 6),
                ReminderCard(reminder: msg['reminder'] as Reminder),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTypingIndicator(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFF534AB7).withValues(alpha: 0.15),
            child: const Text(
              'Z',
              style: TextStyle(
                color: Color(0xFF534AB7),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BounceDot(delay: 0),
                const SizedBox(width: 4),
                _BounceDot(delay: 180),
                const SizedBox(width: 4),
                _BounceDot(delay: 360),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListeningBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: const Color(0xFFE65100).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          _PulseDot(),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Listening... auto-sends after a quiet pause',
              style: TextStyle(color: Color(0xFFE65100), fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: () => _stopListening(send: false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFFE65100),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final chip = _suggestions[i];
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _send(chip);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEEEDFE),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFAFA9EC), width: 0.5),
              ),
              child: Text(
                chip,
                style: const TextStyle(fontSize: 12, color: Color(0xFF534AB7)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputRow(ColorScheme scheme) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.88),
            border: Border(
              top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.3)),
            ),
          ),
          child: Row(
            children: [
              // Mic button
              GestureDetector(
                onTap: _speechAvailable
                    ? _toggleVoiceInput
                    : () => _addBotMessage(
                          "Microphone isn't available. Check mic permissions in Settings.",
                        ),
                child: ScaleTransition(
                  scale: _micScale,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isListening
                          ? const Color(0xFFFFF3E0)
                          : scheme.surfaceContainerHighest,
                      border: Border.all(
                        color: _isListening
                            ? const Color(0xFFE65100)
                            : scheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                      boxShadow: _isListening
                          ? [
                              BoxShadow(
                                color: const Color(0xFFE65100)
                                    .withValues(alpha: 0.25),
                                blurRadius: 18,
                                spreadRadius: 3,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      _isListening
                          ? Icons.mic
                          : (_speechAvailable ? Icons.mic_none : Icons.mic_off),
                      size: 20,
                      color: _isListening
                          ? const Color(0xFFE65100)
                          : _speechAvailable
                              ? scheme.onSurface.withValues(alpha: 0.6)
                              : scheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Text input
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  onSubmitted: (_) => _send(),
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  minLines: 1,
                  maxLines: 5,
                  enabled: !_isLoading,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Say or type anything...',
                    hintStyle: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.4),
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Send button
              GestureDetector(
                onTap: _isLoading ? null : _send,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isLoading
                        ? const Color(0xFF534AB7).withValues(alpha: 0.5)
                        : const Color(0xFF534AB7),
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Animation helpers ──────────────────────────────────────────────────────

class _BounceDot extends StatefulWidget {
  final int delay;
  const _BounceDot({required this.delay});

  @override
  State<_BounceDot> createState() => _BounceDotState();
}

class _BounceDotState extends State<_BounceDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _anim = Tween<double>(
      begin: 0,
      end: -6,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, _anim.value),
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _c,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFE65100),
          ),
        ),
      );
}
