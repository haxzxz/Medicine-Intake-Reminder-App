import 'package:flutter_test/flutter_test.dart';
import 'package:zam_medicine_reminder/models/reminder.dart';

void main() {
  test('recurring reminders advance to a future occurrence', () {
    final reminder = Reminder(
      id: 1,
      medicineName: 'Vitamin C',
      time: DateTime.now().subtract(const Duration(days: 2)),
      recurrence: 'daily',
    );

    final next = reminder.nextOccurrence();

    expect(next.isRecurring, isTrue);
    expect(next.fired, isFalse);
    expect(next.time.isAfter(DateTime.now()), isTrue);
  });
}
