import 'package:dalili_triage/triage/rules_engine.dart';
import 'package:dalili_triage/triage/triage_result.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('RulesEngine — priority and first match', () {
    test('evaluates in ascending priority and the first match wins', () {
      final engine = RulesEngine.fromJsonString(kPriorityRulesJson);
      final result = engine.evaluate(
        fixtureSymptoms(
          ageMonths: 30,
          signs: const {'sign_a': true, 'sign_b': true},
        ),
      );

      // fx_sign_b (priority 10) beats fx_sign_a (20) and fx_both (30).
      expect(result.outcome, Outcome.urgentReferral);
      expect(result.ruleId, 'fx_sign_b');
      expect(result.sourceDoc, 'fixture-doc');
      expect(result.sourcePage, 10);
    });

    test(
      'falls through to the next priority when the first does not match',
      () {
        final engine = RulesEngine.fromJsonString(kPriorityRulesJson);
        final result = engine.evaluate(
          fixtureSymptoms(
            ageMonths: 30,
            signs: const {'sign_a': true, 'sign_b': false},
          ),
        );

        expect(result.outcome, Outcome.homeCare);
        expect(result.ruleId, 'fx_sign_a');
      },
    );

    test('rules are ordered ascending regardless of their order in JSON', () {
      final engine = RulesEngine.fromJsonString(kPriorityRulesJson);
      expect(engine.rules.map((rule) => rule.priority).toList(), <int>[
        5,
        10,
        20,
        30,
      ]);
    });
  });

  group('RulesEngine — null is unknown, not false', () {
    test('a null field does not satisfy an "is: false" condition', () {
      final engine = RulesEngine.fromJsonString(kPriorityRulesJson);

      // sign_a is unknown, sign_b is known. If null were coerced to false,
      // fx_false_sign_a (priority 5) would win with homeCare.
      final result = engine.evaluate(
        fixtureSymptoms(ageMonths: 30, signs: const {'sign_b': true}),
      );

      expect(result.outcome, Outcome.urgentReferral);
      expect(result.ruleId, 'fx_sign_b');
    });
  });
  group('RulesEngine — missing fields', () {
    test(
      'no match plus a null field yields needsMoreInfo listing the field',
      () {
        final engine = RulesEngine.fromJsonString(kMissingFieldRulesJson);
        final result = engine.evaluate(
          fixtureSymptoms(ageMonths: 30, signs: const {'sign_b': true}),
        );

        expect(result.outcome, Outcome.needsMoreInfo);
        expect(result.missingFields, <String>['sign_a']);
        expect(result.ruleId, isNull);
        expect(result.sourceDoc, isNull);
        expect(result.followUpQuestions, isEmpty);
      },
    );

    test('no match with every field known yields the configured outcome', () {
      final engine = RulesEngine.fromJsonString(
        kMissingFieldRulesJson,
        noMatchOutcome: Outcome.outOfScope,
      );
      final result = engine.evaluate(
        fixtureSymptoms(ageMonths: 30, signs: const {'sign_a': false}),
      );

      expect(result.outcome, Outcome.outOfScope);
      expect(result.missingFields, isEmpty);
      expect(result.ruleId, isNull);
    });
  });

  group('RulesEngine — any_of / all_of nesting', () {
    test('a nested all_of inside any_of can satisfy the rule', () {
      final engine = RulesEngine.fromJsonString(kNestingRulesJson);
      final result = engine.evaluate(
        fixtureSymptoms(signs: const {'sign_a': true, 'sign_b': true}),
      );

      expect(result.outcome, Outcome.referOrTreatAtClinic);
      expect(result.ruleId, 'fx_nested');
    });

    test('the second any_of branch can satisfy the rule', () {
      final engine = RulesEngine.fromJsonString(kNestingRulesJson);
      final result = engine.evaluate(
        fixtureSymptoms(
          signs: const {'sign_a': true, 'sign_b': false, 'sign_c': false},
        ),
      );

      expect(result.outcome, Outcome.referOrTreatAtClinic);
      expect(result.ruleId, 'fx_nested');
    });

    test(
      'an unsatisfied any_of with an unknown branch yields needsMoreInfo',
      () {
        final engine = RulesEngine.fromJsonString(kNestingRulesJson);
        final result = engine.evaluate(
          fixtureSymptoms(signs: const {'sign_a': true, 'sign_b': false}),
        );

        expect(result.outcome, Outcome.needsMoreInfo);
        expect(result.missingFields, <String>['sign_c']);
      },
    );
  });

  group('RulesEngine — gte', () {
    test('matches at the boundary and falls through below it', () {
      final engine = RulesEngine.fromJsonString(kThresholdRulesJson);

      final atBoundary = engine.evaluate(
        fixtureSymptoms(signs: const {'sign_num': 5}),
      );
      expect(atBoundary.ruleId, 'fx_gte_five');

      final belowFirst = engine.evaluate(
        fixtureSymptoms(signs: const {'sign_num': 3}),
      );
      expect(belowFirst.ruleId, 'fx_gte_three');

      final belowAll = engine.evaluate(
        fixtureSymptoms(signs: const {'sign_num': 1}),
      );
      expect(belowAll.outcome, Outcome.outOfScope);
    });

    test('a null field never satisfies a gte condition', () {
      final engine = RulesEngine.fromJsonString(kThresholdRulesJson);
      final result = engine.evaluate(fixtureSymptoms());

      expect(result.outcome, Outcome.needsMoreInfo);
      expect(result.missingFields, <String>['sign_num']);
    });
  });

  group('RulesEngine — JSON loading', () {
    test('accepts a bare array and snake_case source aliases', () {
      final engine = RulesEngine.fromJsonString('''
      [
        {
          "id": "fx_bare",
          "priority": 1,
          "outcome": "home_care",
          "source_doc": "fixture-doc",
          "source_page": 3,
          "conditions": { "field": "sign_a", "is": true }
        }
      ]
      ''');

      final result = engine.evaluate(
        fixtureSymptoms(signs: const {'sign_a': true}),
      );

      expect(result.ruleId, 'fx_bare');
      expect(result.outcome, Outcome.homeCare);
      expect(result.sourceDoc, 'fixture-doc');
      expect(result.sourcePage, 3);
    });

    test('rejects an unknown outcome name', () {
      expect(
        () => RulesEngine.fromJsonString('''
        { "rules": [ {
          "id": "bad",
          "priority": 1,
          "outcome": "not_a_real_outcome",
          "conditions": { "field": "sign_a", "is": true }
        } ] }
        '''),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
