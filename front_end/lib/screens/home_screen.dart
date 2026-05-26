import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'dart:async';
import '../models/reminder.dart';
import '../models/reminder_log.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import '../services/gemini_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/reminder_card.dart';
import 'reminder_log_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final SpeechToText _speech = SpeechToText();
  final ClaudeService _claude = ClaudeService();

  final List<Map<String, dynamic>> _messages = [];
  final List<Reminder> _reminders = [];
  List<String> _suggestions = [];

  Timer? _countdownTimer;
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _isLoading = false;
  bool _disposed = false;
  DateTime? _lastSendTime;
  int _nextId = 1;

  static const List<String> _defaultChips = [
    'yo zam pills 8ish',
    'what meds do I have set?',
    'is it safe to take ibuprofen with food?',
    'remind me in 2 minutes',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.wait([_initSpeech(), _loadData()]);
    _startCountdown();
    final name = AuthService.displayName.split(' ').first;
    _addBotMessage(
      "Hey $name! 👋 I'm Zam, your AI medicine reminder assistant.\n\nTry: \"yo zam pills 8ish\" or ask me anything about your meds!",
      suggestions: _defaultChips,
    );
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (e) => debugPrint('Speech error: ${e.errorMsg}'),
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            _safeSetState(() => _isListening = false);
          }
        },
      );
    } catch (e) {
      debugPrint('Speech init: $e');
    }
  }

  Future<void> _loadData() async {
    // API key comes entirely from .env — no UI input needed
    final saved = await StorageService.loadReminders();
    final remote = await BackendService.loadReminders();
    final byId = {for (final reminder in saved) reminder.id: reminder};
    for (final reminder in remote) {
      byId[reminder.id] = reminder;
    }
    final merged = byId.values.toList();
    final active = <Reminder>[];

    for (final r in merged) {
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
      _reminders.addAll(active);
      if (_reminders.isNotEmpty) {
        _nextId =
            _reminders.map((r) => r.id).reduce((a, b) => a > b ? a : b) + 1;
      }
    });
    await StorageService.saveReminders(_reminders);
    unawaited(BackendService.syncReminders(_reminders));
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      bool changed = false;
      for (var i = 0; i < _reminders.length; i++) {
        final r = _reminders[i];
        if (!r.fired && r.time.isBefore(DateTime.now())) {
          changed = true;
          _logReminder(r, 'fired');
          if (r.isRecurring) {
            final next = r.nextOccurrence();
            _reminders[i] = next;
            _scheduleReminder(next);
          } else {
            r.fired = true;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _addBotMessage(
              "🔔 Time to take your ${r.medicineName}!\nDon't forget to take it with water 💧",
            );
          });
        }
      }
      _safeSetState(() {});
      if (changed) {
        StorageService.saveReminders(_reminders);
        unawaited(BackendService.syncReminders(_reminders));
      }
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

  Future<void> _send([String? override]) async {
    // Debounce: prevent double-fires from voice + keyboard
    final now = DateTime.now();
    if (_lastSendTime != null &&
        now.difference(_lastSendTime!).inMilliseconds < 800) {
      return;
    }
    _lastSendTime = now;

    final text = (override ?? _inputCtrl.text).trim();
    if (text.isEmpty || _isLoading) return;
    _inputCtrl.clear();

    _addUserMessage(text);
    _safeSetState(() => _isLoading = true);

    // Key comes from .env via ClaudeService — no UI dialog needed
    final res = await _claude.chat(userMessage: text, reminders: _reminders);

    Reminder? newReminder;
    if (res.action == 'set_reminder' && res.reminder != null) {
      final intent = res.reminder!;
      final time = _parseTime(intent.time);
      newReminder = Reminder(
        id: _nextId++,
        medicineName: intent.name,
        time: time,
        recurrence: _normaliseRecurrence(intent.recurrence),
      );
      _reminders.add(newReminder);
      await _scheduleReminder(newReminder);
      await StorageService.saveReminders(_reminders);
      unawaited(BackendService.upsertReminder(newReminder));
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
    }

    _safeSetState(() => _isLoading = false);
    _addBotMessage(
      res.message,
      reminder: newReminder,
      suggestions: res.suggestions.isNotEmpty ? res.suggestions : null,
    );
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
    unawaited(BackendService.upsertReminder(next));
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) {
      _addBotMessage(
        "Microphone isn't available. Check mic permissions in Settings.",
      );
      return;
    }
    if (_isListening) {
      await _speech.stop();
      _safeSetState(() => _isListening = false);
      return;
    }
    _safeSetState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          _safeSetState(() => _isListening = false);
          _send(result.recognizedWords);
        } else if (!result.finalResult) {
          _safeSetState(() => _inputCtrl.text = result.recognizedWords);
        }
      },
      localeId: 'en_US',
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 4),
      cancelOnError: true,
    );
  }

  Future<void> _deleteReminder(Reminder r) async {
    await _deleteReminderInternal(r);
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
    if (showMessage) _addBotMessage('Deleted ${r.medicineName}.');
  }

  void _openLog() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ReminderLogScreen()));
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF534AB7),
            ),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirm == true) await AuthService.signOut();
    // Auth stream in main.dart automatically navigates back to LoginScreen
  }

  @override
  void dispose() {
    _disposed = true;
    _countdownTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    if (_isListening) _speech.stop();
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
      body: Column(
        children: [
          if (_reminders.isNotEmpty) _buildRemindersStrip(scheme),
          Expanded(child: _buildMessages(scheme)),
          if (_isLoading) _buildTypingIndicator(scheme),
          if (_isListening) _buildListeningBanner(),
          if (_suggestions.isNotEmpty) _buildSuggestions(),
          _buildInputRow(scheme),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme scheme, TextTheme textTheme) {
    final photoUrl = AuthService.photoUrl;

    return AppBar(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Row(
        children: [
          // Zam avatar
          Stack(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF534AB7).withOpacity(0.15),
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
      actions: [
        // ── Reminder log icon (replaces key icon) ──
        IconButton(
          tooltip: 'Reminder history',
          icon: Icon(
            Icons.history_rounded,
            color: scheme.onSurface.withOpacity(0.6),
            size: 24,
          ),
          onPressed: _openLog,
        ),
        // ── User avatar + sign out ──
        GestureDetector(
          onTap: _signOut,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Tooltip(
              message: 'Sign out (${AuthService.displayName})',
              child: photoUrl != null
                  ? CircleAvatar(
                      radius: 16,
                      backgroundImage: NetworkImage(photoUrl),
                    )
                  : CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(
                        0xFF534AB7,
                      ).withOpacity(0.15),
                      child: Text(
                        AuthService.displayName.isNotEmpty
                            ? AuthService.displayName[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          color: Color(0xFF534AB7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
          height: 1,
          color: scheme.outlineVariant.withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildRemindersStrip(ColorScheme scheme) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withOpacity(0.3)),
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
                    color: scheme.onSurface.withOpacity(0.45),
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
        color: isPast ? Colors.orange.withOpacity(0.08) : scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPast
              ? Colors.orange.withOpacity(0.4)
              : scheme.outlineVariant.withOpacity(0.3),
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
              color: scheme.onSurface.withOpacity(0.4),
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
            backgroundColor: const Color(0xFF534AB7).withOpacity(0.15),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFFFF3E0),
      child: Row(
        children: [
          _PulseDot(),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Listening... speak now',
              style: TextStyle(color: Color(0xFFE65100), fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: _toggleListening,
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
            onTap: () => _send(chip),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withOpacity(0.3)),
        ),
      ),
      child: Row(
        children: [
          // Mic button
          GestureDetector(
            onTap: _toggleListening,
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
                      : scheme.outlineVariant.withOpacity(0.4),
                ),
              ),
              child: Icon(
                _isListening
                    ? Icons.mic
                    : (_speechAvailable ? Icons.mic_none : Icons.mic_off),
                size: 20,
                color: _isListening
                    ? const Color(0xFFE65100)
                    : _speechAvailable
                        ? scheme.onSurface.withOpacity(0.6)
                        : scheme.onSurface.withOpacity(0.3),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Text input
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              onSubmitted: (_) => _send(),
              textInputAction: TextInputAction.send,
              enabled: !_isLoading,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Say or type anything...',
                hintStyle: TextStyle(
                  color: scheme.onSurface.withOpacity(0.4),
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
                    ? const Color(0xFF534AB7).withOpacity(0.5)
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
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
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
