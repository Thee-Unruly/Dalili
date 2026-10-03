import 'package:dalili_triage/triage/symptom_set.dart';
import 'package:test/test.dart';

void main() {
  group('SymptomSet — reading fields by name', () {
    test('reads schema fields', () {
      const symptoms = SymptomSet(
        ageMonths: 24,
        coughOrDifficultyBreathing: true,
        breathsPerMinute: 30,
      );

      expect(symptoms.valueFor('ageMonths'), 24);
      expect(symptoms.valueFor('coughOrDifficultyBreathing'), true);
      expect(symptoms.valueFor('breathsPerMinute'), 30);
      expect(symptoms.valueFor('bloodInStool'), isNull);
    });

    test('reads extra fields', () {
      const symptoms = SymptomSet(
        additionalFields: {'sign_a': true, 'sign_b': 7},
      );

      expect(symptoms.valueFor('sign_a'), true);
      expect(symptoms.valueFor('sign_b'), 7);
      expect(symptoms['sign_a'], true); // operator []
    });

    test('unknown names read as null and are not "known"', () {
      const symptoms = SymptomSet();

      expect(symptoms.valueFor('nope'), isNull);
      expect(symptoms.hasField('nope'), isFalse);
      expect(symptoms.isKnown('ageMonths'), isFalse);
      expect(symptoms.unknownFields, contains('ageMonths'));
    });

    test('a present-but-false field is known and is not null', () {
      const symptoms = SymptomSet(bloodInStool: false);

      expect(symptoms.isKnown('bloodInStool'), isTrue);
      expect(symptoms.valueFor('bloodInStool'), isFalse);
      expect(symptoms.unknownFields, isNot(contains('bloodInStool')));
    });
  });

  group('SymptomSet — toMap / fromMap', () {
    test('round-trips known fields and extra fields', () {
      const original = SymptomSet(
        ageMonths: 18,
        diarrhoeaDays: 3,
        bloodInStool: false,
        additionalFields: {'sign_a': true},
      );

      final map = original.toMap();
      expect(map['ageMonths'], 18);
      expect(map['diarrhoeaDays'], 3);
      expect(map['bloodInStool'], false);
      expect(map['sign_a'], true);
      expect(map.containsKey('feverDays'), isFalse); // unknown field omitted

      expect(SymptomSet.fromMap(map), original);
    });

    test('missing keys come back as unknown (null), never false', () {
      final restored = SymptomSet.fromMap(const {'ageMonths': 12});

      expect(restored.ageMonths, 12);
      expect(restored.feverDays, isNull);
      expect(restored.vomitsEverything, isNull);
      expect(restored.unknownFields, contains('feverDays'));
    });

    test('coerces lenient numeric and boolean values', () {
      final restored = SymptomSet.fromMap(const {
        'ageMonths': '30',
        'feverDays': 4.0,
        'convulsions': 'true',
        'bloodInStool': 'false',
      });

      expect(restored.ageMonths, 30);
      expect(restored.feverDays, 4);
      expect(restored.convulsions, isTrue);
      expect(restored.bloodInStool, isFalse);
    });
  });
}
