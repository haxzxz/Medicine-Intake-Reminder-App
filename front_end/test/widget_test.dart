import 'package:flutter_test/flutter_test.dart';
import 'package:zam_medicine_reminder/models/reminder.dart';
import 'package:zam_medicine_reminder/services/reminder_text_parser.dart';

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

  test('allergy questions are safety questions, not reminder status questions',
      () {
    const text = "what medicine can i take if i'm having an allergy reaction";

    expect(ReminderTextParser.isAllergicReactionQuestion(text), isTrue);
    expect(ReminderTextParser.isReminderStatusQuestion(text), isFalse);
  });

  test('allergy safety response includes disclaimer and location caveat', () {
    final response =
        ReminderTextParser.allergySafetyResponse(countryCode: 'SG');

    expect(response, contains('995, based on your device region'));
    expect(response, contains('may or may not work'));
    expect(response,
        contains('Zam is for reminder scheduling and convenience only'));
    expect(response, contains('Always consult a healthcare professional'));
  });

  test('symptom medicine questions use safety response', () {
    const text = 'hey zam I have headache what medicine should I take';

    expect(ReminderTextParser.isSymptomMedicationQuestion(text), isTrue);
    expect(ReminderTextParser.isReminderStatusQuestion(text), isFalse);
  });

  test('symptom safety response refuses medical advice and has red flags', () {
    final response =
        ReminderTextParser.symptomMedicationSafetyResponse(countryCode: 'SG');

    expect(response, contains("I can't tell you what medicine to take"));
    expect(response, contains('995, based on your device region'));
    expect(response, contains('worst headache of your life'));
    expect(response, contains('may or may not work'));
    expect(response, contains('Always consult a healthcare professional'));
  });

  test('US allergy safety response includes Poison Control', () {
    final response =
        ReminderTextParser.allergySafetyResponse(countryCode: 'US');

    expect(response, contains('911, based on your device region'));
    expect(response, contains('1-800-222-1222'));
  });

  test('clock-time reminder text parses one correct medicine name and time',
      () {
    final parsedTime = ReminderTextParser.clockTimeFromText(
      'remind me at 1:30 a.m to drink paracetamol',
      now: DateTime(2026, 6, 1, 1, 28, 16),
    );
    final medicineName = ReminderTextParser.medicineNameFromClockText(
      'remind me at 1:30 a.m to drink paracetamol',
    );

    expect(parsedTime, DateTime(2026, 6, 1, 1, 30));
    expect(medicineName, 'Paracetamol');
  });

  test('clock-time parser rolls past times to tomorrow', () {
    final parsedTime = ReminderTextParser.clockTimeFromText(
      'take paracetamol at 1:30 am',
      now: DateTime(2026, 6, 1, 1, 31),
    );

    expect(parsedTime, DateTime(2026, 6, 2, 1, 30));
  });

  test('punctuation-only medicine names fall back to generic medicine', () {
    expect(ReminderTextParser.cleanMedicineName('.', '.'), 'Medicine');
    expect(ReminderTextParser.cleanMedicineName(' . ', 'set . for 35s'),
        'Medicine');
  });

  test('medicine names trim surrounding punctuation but keep real words', () {
    expect(ReminderTextParser.cleanMedicineName('paracetamol.', 'paracetamol.'),
        'Paracetamol');
  });

  test('delete all reminders request is detected before status listing', () {
    const text = 'delete all my reminders';

    expect(ReminderTextParser.isDeleteAllReminderRequest(text), isTrue);
    expect(ReminderTextParser.isReminderStatusQuestion(text), isFalse);
  });
}
