import 'package:dalili_triage/triage/rules_engine.dart';
import 'package:dalili_triage/triage/safety_gate.dart';
import 'package:dalili_triage/triage/symptom_set.dart';
import 'package:dalili_triage/triage/triage_result.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  late SafetyGate gate;
  setUp(() {
    gate = SafetyGate.fromJsonString(
      kFakeQuestionsJson,
      minAgeMonths: kFixtureMinAgeMonths,
      maxAgeMonths: kFixtureMaxAgeMonths,
    );
  });

  group('SafetyGate — age scope (runs before the engine)', () {
    test('a null age yields needsMoreInfo with the age question', () {
      final result = gate.gate(const SymptomSet());

      expect(result, isNotNull);
      expect(result!.outcome, Outcome.needsMoreInfo);
      expect(result.missingFields, <String>['ageMonths']);
      expect(result.followUpQuestions, <String>[
        'Fixture question for ageMonths?',
      ]);
    });

    test('an age below the minimum is out of scope', () {
      final result = gate.gate(
        const SymptomSet(ageMonths: kFixtureMinAgeMonths - 1),
      );

      expect(result!.outcome, Outcome.outOfScope);
      expect(result.reason, 'outside guideline age range, refer');
      expect(result.ruleId, isNull);
    });

    test('an age above the maximum is out of scope', () {
      final result = gate.gate(
        const SymptomSet(ageMonths: kFixtureMaxAgeMonths + 1),
      );

      expect(result!.outcome, Outcome.outOfScope);
      expect(result.reason, 'outside guideline age range, refer');
    });

    test('an age inside the range passes the gate', () {
      expect(
        gate.gate(const SymptomSet(ageMonths: kFixtureMinAgeMonths)),
        isNull,
      );
      expect(
        gate.gate(const SymptomSet(ageMonths: kFixtureMaxAgeMonths)),
        isNull,
      );
    });
  });

  group('SafetyGate — follow-up questions (runs after the engine)', () {
    test('attaches one question per missing field', () {
      final engine = RulesEngine.fromJsonString(kMissingFieldRulesJson);
      final result = gate.evaluate(
        fixtureSymptoms(ageMonths: 30, signs: const {'sign_b': true}),
        engine,
      );

      expect(result.outcome, Outcome.needsMoreInfo);
      expect(result.missingFields, <String>['sign_a']);
      expect(result.followUpQuestions, <String>[
        'Fixture question for sign_a?',
      ]);
    });

    test('uses a neutral fallback when no question is supplied', () {
      final bare = SafetyGate(
        minAgeMonths: kFixtureMinAgeMonths,
        maxAgeMonths: kFixtureMaxAgeMonths,
      );

      expect(
        bare.questionFor('sign_z'),
        'Please provide a value for "sign_z".',
      );
    });

    test('a decision is returned unchanged (no questions attached)', () {
      final engine = RulesEngine.fromJsonString(kPriorityRulesJson);
      final result = gate.evaluate(
        fixtureSymptoms(
          ageMonths: 30,
          signs: const {'sign_a': true, 'sign_b': true},
        ),
        engine,
      );

      expect(result.outcome, Outcome.urgentReferral);
      expect(result.ruleId, 'fx_sign_b');
      expect(result.followUpQuestions, isEmpty);
    });
  });

  group('SafetyGate — never outputs a diagnosis', () {
    test('non-decision results carry no rule, source, or classification', () {
      final engine = RulesEngine.fromJsonString(kMissingFieldRulesJson);
      final needsInfo = gate.evaluate(fixtureSymptoms(ageMonths: 30), engine);
      expect(needsInfo.outcome, Outcome.needsMoreInfo);
      expect(needsInfo.ruleId, isNull);
      expect(needsInfo.sourceDoc, isNull);
      expect(needsInfo.sourcePage, isNull);

      final outOfScope = gate.gate(const SymptomSet(ageMonths: 1));
      expect(outOfScope!.outcome, Outcome.outOfScope);
      expect(outOfScope.ruleId, isNull);
      expect(outOfScope.sourceDoc, isNull);
    });
  });
}
