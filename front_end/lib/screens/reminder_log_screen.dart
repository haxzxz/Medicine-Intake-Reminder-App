import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/reminder_log.dart';
import '../services/storage_service.dart';

class ReminderLogScreen extends StatefulWidget {
  final bool embedded;
  final int refreshToken;

  const ReminderLogScreen({
    super.key,
    this.embedded = false,
    this.refreshToken = 0,
  });

  @override
  State<ReminderLogScreen> createState() => _ReminderLogScreenState();
}

class _ReminderLogScreenState extends State<ReminderLogScreen> {
  List<ReminderLog> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void didUpdateWidget(covariant ReminderLogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _loadLogs();
    }
  }

  Future<void> _loadLogs() async {
    final logs = await StorageService.loadLogs();
    setState(() {
      // Show newest first
      _logs = logs.reversed.toList();
      _loading = false;
    });
  }

  Future<void> _clearAll() async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear all logs?'),
        content: const Text(
          'This will permanently delete your entire reminder history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              HapticFeedback.heavyImpact();
              Navigator.pop(context, true);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await StorageService.clearLogs();
      setState(() => _logs = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _logs.isEmpty
            ? _buildEmpty(scheme)
            : _buildList(scheme);

    if (widget.embedded) {
      return Column(
        children: [
          _buildEmbeddedHeader(scheme),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reminder Log',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
            ),
            Text(
              '${_logs.length} entries',
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.45),
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          if (_logs.isNotEmpty)
            IconButton(
              tooltip: 'Clear all',
              icon: Icon(
                Icons.delete_sweep_outlined,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
              onPressed: _clearAll,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      body: body,
    );
  }

  Widget _buildEmbeddedHeader(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reminder Logs',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
                Text(
                  '${_logs.length} entries',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.45),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (_logs.isNotEmpty)
            IconButton(
              tooltip: 'Clear all',
              icon: Icon(
                Icons.delete_sweep_outlined,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
              onPressed: _clearAll,
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF534AB7).withValues(alpha: 0.08),
            ),
            child: const Icon(
              Icons.history_rounded,
              size: 36,
              color: Color(0xFF534AB7),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No reminders yet',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your reminder history will appear here',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme scheme) {
    // Group by date
    final Map<String, List<ReminderLog>> grouped = {};
    for (final log in _logs) {
      final key = _dateKey(log.firedAt);
      grouped.putIfAbsent(key, () => []).add(log);
    }

    final sections = grouped.entries.toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: sections.length,
      itemBuilder: (_, i) {
        final section = sections[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                _friendlyDate(section.value.first.firedAt),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                  letterSpacing: 0.6,
                ),
              ),
            ),
            ...section.value.map((log) => _buildLogCard(log, scheme)),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildLogCard(ReminderLog log, ColorScheme scheme) {
    final timeFmt = DateFormat('h:mm a');
    final isFired = log.status == 'fired';
    final isMissed = log.status == 'missed';
    final isSnoozed = log.status == 'snoozed';
    final isDeleted = log.status == 'deleted';

    final statusColor = isFired
        ? const Color(0xFF1D9E75)
        : isMissed
            ? Colors.orange
            : isSnoozed
                ? const Color(0xFF534AB7)
                : scheme.onSurface.withValues(alpha: 0.4);

    final statusIcon = isFired
        ? Icons.check_circle_outline_rounded
        : isMissed
            ? Icons.warning_amber_rounded
            : isSnoozed
                ? Icons.snooze_rounded
                : Icons.cancel_outlined;

    final statusLabel = isFired
        ? 'Taken'
        : isMissed
            ? 'Missed'
            : isSnoozed
                ? 'Snoozed'
                : isDeleted
                    ? 'Deleted'
                    : log.status;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 72,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 20,
            backgroundColor: statusColor.withValues(alpha: 0.12),
            child: Icon(statusIcon, color: statusColor, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        log.medicineName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 12,
                      color: scheme.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Scheduled ${timeFmt.format(log.scheduledTime)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.notifications_active_outlined,
                      size: 12,
                      color: scheme.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${isSnoozed ? 'Snoozed' : isDeleted ? 'Deleted' : isFired ? 'Taken' : 'Marked missed'} at ${timeFmt.format(log.firedAt)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    if (!isFired) ...[
                      const SizedBox(width: 6),
                      Text(
                        _delay(log.scheduledTime, log.firedAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: isMissed ? Colors.orange : statusColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _friendlyDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(d.year, d.month, d.day);
    final diff = today.difference(date).inDays;
    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    return DateFormat('MMMM d, yyyy').format(d).toUpperCase();
  }

  String _delay(DateTime scheduled, DateTime fired) {
    final diff = fired.difference(scheduled);
    if (diff.inMinutes < 1) return '';
    if (diff.inMinutes < 60) return '(+${diff.inMinutes}m late)';
    return '(+${diff.inHours}h late)';
  }
}
