import 'dart:ui';

class ReminderTextParser {
  static bool isAllergicReactionQuestion(String text) {
    final normalized = text.toLowerCase();
    return RegExp(
      r'\b(allergy|allergic|allergic reaction|anaphylaxis|hives|swelling|throat|trouble breathing|shortness of breath)\b',
    ).hasMatch(normalized);
  }

  static bool isSymptomMedicationQuestion(String text) {
    final normalized = text.toLowerCase();
    final hasSymptom = RegExp(
      r'\b(headache|migraine|fever|cough|sore throat|stomach ache|stomachache|nausea|vomiting|diarrhea|dizzy|dizziness|pain|chest pain|rash|cramps|cold|flu)\b',
    ).hasMatch(normalized);
    final asksMedicine = RegExp(
      r'\b(what|which|any)\s+(medicine|medicines|meds|pill|pills|drug|drugs)\b.*\b(take|use|drink)\b|\b(what|which)\s+.*\b(can|should|do)\s+i\s+(take|use|drink)\b',
    ).hasMatch(normalized);
    final statesSymptom =
        RegExp(r"\b(i have|i'm having|i am having|having|got)\b")
            .hasMatch(normalized);
    return hasSymptom && (asksMedicine || statesSymptom);
  }

  static bool isReminderStatusQuestion(String text) {
    final normalized = text.toLowerCase();
    if (isDeleteAllReminderRequest(text)) return false;
    if (RegExp(
      r'\b(what|which)\s+(medicine|medicines|meds|pill|pills)\s+(can|should|do)\s+i\s+take\b',
    ).hasMatch(normalized)) {
      return false;
    }
    return RegExp(
          r'\b(what|check|show|list|view|see)\b.*\b(reminder|reminders|meds|medicine|medicines)\b',
        ).hasMatch(normalized) ||
        RegExp(r'\b(my|active|upcoming)\s+(reminder|reminders|meds|medicine|medicines)\b')
            .hasMatch(normalized) ||
        normalized.contains('what do i have set');
  }

  static bool isDeleteAllReminderRequest(String text) {
    final normalized = text.toLowerCase();
    return RegExp(
      r'\b(delete|remove|clear|cancel)\b.*\b(all|every|everything)\b.*\b(reminder|reminders|meds|medicine|medicines|pills)\b',
    ).hasMatch(normalized);
  }

  static String allergySafetyResponse({String? countryCode}) {
    final emergencyNumber = emergencyNumberForRegion(countryCode);
    final poisonHelp = poisonHelpForRegion(countryCode);
    final poisonLine = poisonHelp == null ? '' : '\n\n$poisonHelp';
    return "If you're having an allergic reaction, please get medical help now. If you have trouble breathing, throat/face swelling, faintness, or symptoms are getting worse, call $emergencyNumber immediately.$poisonLine\n\nHotline numbers depend on your country or region and may or may not work from your current location, carrier, or device.\n\nI can't tell you what medicine to take for an allergic reaction. Zam is for reminder scheduling and convenience only. Always consult a healthcare professional about medical advice, dosages, and drug interactions.";
  }

  static String symptomMedicationSafetyResponse({String? countryCode}) {
    final emergencyNumber = emergencyNumberForRegion(countryCode);
    return "I'm sorry you're feeling that. I can't tell you what medicine to take for symptoms like headache, fever, pain, cough, stomach symptoms, or dizziness.\n\nIf symptoms are severe, sudden, unusual, getting worse, or come with red flags like chest pain, trouble breathing, fainting, confusion, stiff neck, weakness/numbness, severe allergic symptoms, or the worst headache of your life, call $emergencyNumber or seek urgent medical care now.\n\nHotline numbers depend on your country or region and may or may not work from your current location, carrier, or device.\n\nZam is for reminder scheduling and convenience only. Always consult a healthcare professional about medical advice, dosages, and drug interactions.";
  }

  static String emergencyNumberForRegion([String? countryCode]) {
    final country =
        (countryCode ?? PlatformDispatcher.instance.locale.countryCode ?? '')
            .toUpperCase();
    const emergencyNumbers = {
      'AU': '000',
      'CA': '911',
      'DE': '112',
      'ES': '112',
      'FR': '112',
      'GB': '999 or 112',
      'ID': '112',
      'IE': '112 or 999',
      'IN': '112',
      'IT': '112',
      'JP': '119',
      'KR': '119',
      'MY': '999',
      'NL': '112',
      'NZ': '111',
      'PH': '911',
      'SG': '995',
      'US': '911',
    };
    final number = emergencyNumbers[country];
    if (number == null) return 'your local emergency number';
    return '$number, based on your device region';
  }

  static String? poisonHelpForRegion([String? countryCode]) {
    final country =
        (countryCode ?? PlatformDispatcher.instance.locale.countryCode ?? '')
            .toUpperCase();
    if (country == 'US') {
      return 'For possible poisoning, overdose, or accidental exposure in the US, Poison Control is 1-800-222-1222.';
    }
    return null;
  }

  static DateTime? clockTimeFromText(String text, {DateTime? now}) {
    final match = RegExp(
      r'\b(?:at|around)?\s*(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;

    var hour = int.tryParse(match.group(1)!) ?? 0;
    final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
    if (hour < 1 || hour > 12 || minute < 0 || minute > 59) return null;

    final meridiem = match.group(3)!.toLowerCase();
    if (meridiem.startsWith('p') && hour != 12) hour += 12;
    if (meridiem.startsWith('a') && hour == 12) hour = 0;

    final base = now ?? DateTime.now();
    var time = DateTime(base.year, base.month, base.day, hour, minute);
    if (time.isBefore(base.add(const Duration(seconds: 10)))) {
      time = time.add(const Duration(days: 1));
    }
    return time;
  }

  static String medicineNameFromClockText(String text) {
    final match = RegExp(
      r'\b(?:to take|take|to drink|drink)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) {
      return cleanMedicineName(match.group(1) ?? text, text);
    }
    return cleanMedicineName(text, text);
  }

  static String cleanMedicineName(String rawName, [String sourceText = '']) {
    var cleaned = rawName.trim();
    final source = sourceText.trim();
    if (source.isNotEmpty) {
      final withoutTiming = source.replaceAll(
        RegExp(
          r'\b(?:for|in|after)?\s*\d{1,3}\s*(?:m|min|mins|minute|minutes|s|sec|secs|second|seconds)\b',
          caseSensitive: false,
        ),
        ' ',
      );
      final medMatches = RegExp(
        r"\b(?:for|take|taking|to take|drink|to drink)\s+(?:my\s+)?([a-z][a-z0-9 \-'’]*)\s+(?:medicine|meds|pill|pills|dose)\b",
        caseSensitive: false,
      ).allMatches(withoutTiming).toList();
      final medMatch = medMatches.isEmpty ? null : medMatches.last;
      if (medMatch != null) {
        cleaned = medMatch.group(1)?.trim() ?? cleaned;
      }
    }

    cleaned = cleaned
        .replaceAll(
          RegExp(
            r'\b(um|uh|hmm|hm|please|pls|hey|yo|zam|set|create|add|make|a|an|the|my|now|remind me|reminder|remind|to take|take|taking|to drink|drink|medicine|meds|pill|pills|dose|in|after|for|at|around)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b\d{1,2}(?::\d{2})?\s*(a\.?m\.?|p\.?m\.?)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b\d{1,3}\s*(m|min|mins|minute|minutes|s|sec|secs|second|seconds)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .trim();
    cleaned = cleaned.replaceAll(
        RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty ||
        !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(cleaned)) {
      return 'Medicine';
    }
    return cleaned
        .split(' ')
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }
}
