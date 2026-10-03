/// Clearly-fake fixtures for the triage-core tests.
///
/// Nothing here encodes a clinical claim. Field names are `sign_a`, `sign_b`,
/// `sign_c`, and `sign_num`; source documents are `fixture-doc`; the age bounds
/// are arbitrary. Real rules and questions arrive later as data.
library;

import 'package:dalili_triage/triage/symptom_set.dart';

/// Fake age bounds (months). NOT a guideline range.
const int kFixtureMinAgeMonths = 10;
const int kFixtureMaxAgeMonths = 50;

/// Builds a [SymptomSet] with arbitrary fixture signs.
SymptomSet fixtureSymptoms({
  int? ageMonths,
  Map<String, Object?> signs = const <String, Object?>{},
}) => SymptomSet(ageMonths: ageMonths, additionalFields: signs);

/// Several rules can match at once, so this exercises priority + first-match.
const String kPriorityRulesJson = '''
{
  "rules": [
    {
      "id": "fx_false_sign_a",
      "priority": 5,
      "outcome": "homeCare",
      "sourceDoc": "fixture-doc",
      "sourcePage": 5,
      "conditions": { "field": "sign_a", "is": false }
    },
    {
      "id": "fx_sign_b",
      "priority": 10,
      "outcome": "urgentReferral",
      "sourceDoc": "fixture-doc",
      "sourcePage": 10,
      "conditions": { "field": "sign_b", "is": true }
    },
    {
      "id": "fx_sign_a",
      "priority": 20,
      "outcome": "homeCare",
      "sourceDoc": "fixture-doc",
      "sourcePage": 20,
      "conditions": { "field": "sign_a", "is": true }
    },
    {
      "id": "fx_both",
      "priority": 30,
      "outcome": "referOrTreatAtClinic",
      "sourceDoc": "fixture-doc",
      "sourcePage": 30,
      "conditions": {
        "all_of": [
          { "field": "sign_a", "is": true },
          { "field": "sign_b", "is": true }
        ]
      }
    }
  ]
}
''';

/// A single rule whose only field (`sign_a`) the caller can leave unknown.
const String kMissingFieldRulesJson = '''
{
  "rules": [
    {
      "id": "fx_needs_sign_a",
      "priority": 10,
      "outcome": "homeCare",
      "sourceDoc": "fixture-doc",
      "sourcePage": 1,
      "conditions": { "field": "sign_a", "is": true }
    }
  ]
}
''';

/// `all_of` nested inside `any_of`, plus a second top-level branch.
const String kNestingRulesJson = '''
{
  "rules": [
    {
      "id": "fx_nested",
      "priority": 10,
      "outcome": "referOrTreatAtClinic",
      "sourceDoc": "fixture-doc",
      "sourcePage": 7,
      "conditions": {
        "any_of": [
          {
            "all_of": [
              { "field": "sign_a", "is": true },
              { "field": "sign_b", "is": true }
            ]
          },
          { "field": "sign_c", "is": false }
        ]
      }
    }
  ]
}
''';

/// Two `gte` rules at different priorities, for boundary testing.
const String kThresholdRulesJson = '''
{
  "rules": [
    {
      "id": "fx_gte_five",
      "priority": 10,
      "outcome": "homeCare",
      "sourceDoc": "fixture-doc",
      "sourcePage": 1,
      "conditions": { "field": "sign_num", "gte": 5 }
    },
    {
      "id": "fx_gte_three",
      "priority": 20,
      "outcome": "referOrTreatAtClinic",
      "sourceDoc": "fixture-doc",
      "sourcePage": 2,
      "conditions": { "field": "sign_num", "gte": 3 }
    }
  ]
}
''';

/// Fake `field -> question` map.
const String kFakeQuestionsJson = '''
{
  "ageMonths": "Fixture question for ageMonths?",
  "sign_a": "Fixture question for sign_a?",
  "sign_b": "Fixture question for sign_b?",
  "sign_c": "Fixture question for sign_c?"
}
''';
