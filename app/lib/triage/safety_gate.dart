/// [SafetyGate] guards the deterministic triage core against incomplete or
/// out-of-scope input.
///
/// ## Order of operations
/// 1. **Before** the rules engine, [gate] inspects the [SymptomSet]:
///    * `ageMonths == null` → [Outcome.needsMoreInfo] with the age follow-up
///      question.
///    * `ageMonths` outside `[minAgeMonths, maxAgeMonths]` →
///      [Outcome.outOfScope] with the reason `outside guideline age range,
///      refer`.
/// 2. **After** the rules engine, [enrich] turns an [Outcome.needsMoreInfo]
///    result into one plain-language question per missing field, using the
///    caller-supplied `field -> question` map.
///
/// [evaluate] runs both steps around a [RulesEngine] in the correct order.
///
/// ## No diagnoses
/// This class never names a condition or classification. It only produces
/// actions, the fields that are still unknown, and neutral question text.
///
/// ## No clinical thresholds in code
/// The age bounds are constructor parameters and are **not** set here; the
/// caller supplies them from the guideline being encoded.
library;

import 'dart:convert';

import 'rules_engine.dart';
import 'symptom_set.dart';
import 'triage_result.dart';

/// Runs the age/scope checks and the follow-up-question mapping around a
/// [RulesEngine].
class SafetyGate {
  /// Lowest age (in months) the loaded guideline applies to.
  final int minAgeMonths;

  /// Highest age (in months) the loaded guideline applies to.
  final int maxAgeMonths;

  /// Maps a field name to the plain-language question that fills it in.
  final Map<String, String> questions;

  SafetyGate({
    required this.minAgeMonths,
    required this.maxAgeMonths,
    Map<String, String>? questions,
  }) : questions = Map<String, String>.unmodifiable(
         questions ?? const <String, String>{},
       );

  /// Builds a gate from a JSON question map (and explicit age bounds).
  ///
  /// Accepts either a bare map (`{ "field": "question" }`) or a map wrapped in
  /// `{ "questions": { ... } }`.
  factory SafetyGate.fromJsonString(
    String json, {
    required int minAgeMonths,
    required int maxAgeMonths,
  }) {
    final decoded = jsonDecode(json);
    final source = decoded is Map && decoded['questions'] is Map
        ? decoded['questions']
        : decoded;
    if (source is! Map) {
      throw const FormatException(
        'Question JSON must be a map of field name -> question text.',
      );
    }
    final parsed = <String, String>{};
    source.forEach((key, value) {
      if (value != null) parsed[key.toString()] = value.toString();
    });
    return SafetyGate(
      minAgeMonths: minAgeMonths,
      maxAgeMonths: maxAgeMonths,
      questions: parsed,
    );
  }

  /// Runs **before** the rules engine.
  ///
  /// Returns a blocking [TriageResult] when the input cannot be evaluated, or
  /// `null` when evaluation should continue.
  TriageResult? gate(SymptomSet symptoms) {
    final age = symptoms.ageMonths;

    if (age == null) {
      return TriageResult(
        outcome: Outcome.needsMoreInfo,
        missingFields: const <String>['ageMonths'],
        followUpQuestions: <String>[questionFor('ageMonths')],
        reason:
            'Age is unknown; it is required before any age-scoped rule can '
            'be evaluated.',
      );
    }

    if (age < minAgeMonths || age > maxAgeMonths) {
      return const TriageResult(
        outcome: Outcome.outOfScope,
        reason: 'outside guideline age range, refer',
      );
    }

    return null;
  }

  /// Runs the whole deterministic pipeline: [gate] → [RulesEngine.evaluate] →
  /// [enrich].
  TriageResult evaluate(SymptomSet symptoms, RulesEngine engine) {
    final blocked = gate(symptoms);
    if (blocked != null) return blocked;
    return enrich(engine.evaluate(symptoms));
  }

  /// Runs **after** the rules engine.
  ///
  /// If [result] is [Outcome.needsMoreInfo], attaches one question per field in
  /// [TriageResult.missingFields]. Any other outcome (including every decision)
  /// is returned unchanged.
  TriageResult enrich(TriageResult result) {
    if (result.outcome != Outcome.needsMoreInfo) return result;

    final followUps = <String>[
      for (final field in result.missingFields) questionFor(field),
    ];

    return result.copyWith(followUpQuestions: followUps);
  }

  /// The question text for [field].
  ///
  /// Falls back to a neutral, non-clinical template when the caller did not
  /// supply one.
  String questionFor(String field) {
    final question = questions[field];
    if (question != null && question.trim().isNotEmpty) return question;
    return 'Please provide a value for "$field".';
  }
}
