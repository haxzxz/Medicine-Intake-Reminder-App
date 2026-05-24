class Reminder {
  final int id;
  final String medicineName;
  final DateTime time;
  final DateTime createdAt; // when the user set this reminder
  final String recurrence; // 'none' | 'daily' | 'weekly'
  bool fired;

  Reminder({
    required this.id,
    required this.medicineName,
    required this.time,
    DateTime? createdAt,
    this.recurrence = 'none',
    this.fired = false,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isRecurring => recurrence == 'daily' || recurrence == 'weekly';

  bool get isPast => time.isBefore(DateTime.now());

  String get timeUntilLabel {
    final diff = time.difference(DateTime.now());
    if (diff.isNegative) {
      return 'Fired!';
    }
    if (diff.inHours > 0) {
      return 'in ${diff.inHours}h ${diff.inMinutes % 60}m';
    }
    if (diff.inMinutes > 0) {
      return 'in ${diff.inMinutes}m ${diff.inSeconds % 60}s';
    }
    return 'in ${diff.inSeconds}s';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'medicineName': medicineName,
        'time': time.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'recurrence': recurrence,
        'fired': fired,
      };

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        id: json['id'] as int,
        medicineName: json['medicineName'] as String,
        time: DateTime.parse(json['time'] as String),
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
        recurrence: json['recurrence'] as String? ?? 'none',
        fired: json['fired'] as bool? ?? false,
      );

  Reminder copyWith({
    int? id,
    String? medicineName,
    DateTime? time,
    DateTime? createdAt,
    String? recurrence,
    bool? fired,
  }) {
    return Reminder(
      id: id ?? this.id,
      medicineName: medicineName ?? this.medicineName,
      time: time ?? this.time,
      createdAt: createdAt ?? this.createdAt,
      recurrence: recurrence ?? this.recurrence,
      fired: fired ?? this.fired,
    );
  }

  Reminder nextOccurrence({DateTime? after}) {
    final duration = recurrence == 'weekly'
        ? const Duration(days: 7)
        : recurrence == 'daily'
            ? const Duration(days: 1)
            : null;
    if (duration == null) return this;

    final threshold = after ?? DateTime.now();
    var next = time.add(duration);
    while (!next.isAfter(threshold)) {
      next = next.add(duration);
    }
    return copyWith(time: next, fired: false);
  }
}
