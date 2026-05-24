/// A single entry in the reminder history log.
/// Created whenever a reminder fires, is missed, is snoozed, or is deleted.
class ReminderLog {
  final int reminderId;
  final String medicineName;
  final DateTime scheduledTime;
  final DateTime firedAt;
  final String status; // 'fired' | 'missed' | 'snoozed' | 'deleted'

  ReminderLog({
    required this.reminderId,
    required this.medicineName,
    required this.scheduledTime,
    required this.firedAt,
    this.status = 'fired',
  });

  Map<String, dynamic> toJson() => {
    'reminderId': reminderId,
    'medicineName': medicineName,
    'scheduledTime': scheduledTime.toIso8601String(),
    'firedAt': firedAt.toIso8601String(),
    'status': status,
  };

  factory ReminderLog.fromJson(Map<String, dynamic> json) => ReminderLog(
    reminderId: json['reminderId'] as int,
    medicineName: json['medicineName'] as String,
    scheduledTime: DateTime.parse(json['scheduledTime'] as String),
    firedAt: DateTime.parse(json['firedAt'] as String),
    status: json['status'] as String? ?? 'fired',
  );
}
