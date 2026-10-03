/// Deterministic rules engine for the Dalili triage core.
///
/// ## Contract
/// * Pure Dart. No inference, no Flutter, no database.
/// * Rules are **data**: they are loaded from a JSON string supplied by the
///   caller, so clinical logic stays auditable and updateable without a
///   recompile.
/// * Rules are evaluated in **ascending [Rule.priority]** order and the
///   **first match wins**.
/// * A condition that reads a field which is `null` (unknown) is *not* treated
///   as `false`. Instead the field is recorded as missing, and — if no rule
///   matches — the engine returns [Outcome.needsMoreInfo] rather than a
///   (possibly wrong) decision.
///
/// ## Condition grammar
/// A condition is a JSON object; exactly one of the following shapes:
/// ```jsonc
/// { "field": "f", "is": true }     // equality against a literal
/// { "field": "f", "gte": 3 }       // numeric greater-than-or-equal
/// { "any_of": [ <condition>, ... ] } // true if any child is satisfied
/// { "all_of": [ <condition>, ... ] } // true if every child is satisfied
/// ```
/// `any_of` / `all_of` nest arbitrarily.
library;

import 'dart:convert';

import 'symptom_set.dart';
import 'triage_result.dart';

/// A single triage rule.
class Rule {
  /// Stable unique identifier.
  final String id;

  /// Evaluation order: **lower numbers are evaluated first**.
  final int priority;

  /// The rule's condition tree (see the library doc for the grammar).
  final Map<String, dynamic> conditions;

  /// Action recommended when the rule fires.
  final Outcome outcome;

  /// Guideline document this rule was derived from.
  final String sourceDoc;

  /// Page within [sourceDoc].
  final int? sourcePage;

  const Rule({
    required this.id,
    required this.priority,
    required this.conditions,
    required this.outcome,
    required this.sourceDoc,
    this.sourcePage,
  });

  /// Parses a single rule from JSON. Throws [FormatException] on bad input.
  factory Rule.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Rule is missing a non-empty "id".');
    }

    final priority = json['priority'];
    if (priority is! int) {
      throw FormatException('Rule "$id" is missing an integer "priority".');
    }

    final rawConditions = json['conditions'];
    if (rawConditions is! Map) {
      throw FormatException('Rule "$id" is missing a "conditions" object.');
    }

    return Rule(
      id: id,
      priority: priority,
      conditions: Map<String, dynamic>.from(rawConditions),
      outcome: parseOutcome(json['outcome'], id),
      sourceDoc: (json['sourceDoc'] ?? json['source_doc'] ?? '') as String,
      sourcePage: json['sourcePage'] as int? ?? json['source_page'] as int?,
    );
  }

  /// Maps an outcome name from JSON to an [Outcome].
  ///
  /// Accepts the enum name (`urgentReferral`) or a snake-case spelling
  /// (`urgent_referral`).
  static Outcome parseOutcome(Object? raw, String ruleId) {
    if (raw is String) {
      final normalised = raw
          .toLowerCase()
          .replaceAll('_', '')
          .replaceAll('-', '');
      for (final outcome in Outcome.values) {
        if (outcome.name.toLowerCase() == normalised) return outcome;
      }
    }
    throw FormatException('Rule "$ruleId" has an unknown outcome: $raw');
  }
}

/// Tri-state result of evaluating a condition: satisfied, or not, plus the set
/// of fields that were unknown while deciding.
///
/// A not-satisfied condition with a **non-empty** [missing] set is *unknown*
/// (it could still become satisfied); one with an **empty** [missing] set is
/// definitely `false`.
class _Eval {
  final bool satisfied;
  final Set<String> missing;

  const _Eval(this.satisfied, this.missing);

  static const _Eval satisfiedTrue = _Eval(true, <String>{});
  static const _Eval definitelyFalse = _Eval(false, <String>{});

  static _Eval unknown(Set<String> missing) => _Eval(false, missing);
}

/// Evaluates a [SymptomSet] against an ordered table of [Rule]s and returns a
/// [TriageResult].
class RulesEngine {
  /// Rules sorted in ascending [Rule.priority] order (stable for ties).
  final List<Rule> rules;

  /// Outcome to report when no rule matches **and** every field was known.
  /// Defaults to [Outcome.outOfScope] (the loaded guideline does not cover the
  /// case). Rules needing more info are reported separately as
  /// [Outcome.needsMoreInfo].
  final Outcome noMatchOutcome;

  RulesEngine({
    required List<Rule> rules,
    this.noMatchOutcome = Outcome.outOfScope,
  }) : rules = _sortAscending(rules);

  /// Builds an engine from a raw JSON string.
  factory RulesEngine.fromJsonString(
    String json, {
    Outcome noMatchOutcome = Outcome.outOfScope,
  }) => RulesEngine.fromJson(jsonDecode(json), noMatchOutcome: noMatchOutcome);

  /// Builds an engine from already-decoded JSON.
  ///
  /// Accepts `{ "rules": [ ... ] }`, a bare `[ ... ]` array, a single rule
  /// object, or a `{ id: rule, id: rule }` map.
  factory RulesEngine.fromJson(
    Object? decoded, {
    Outcome noMatchOutcome = Outcome.outOfScope,
  }) {
    final ruleList = _extractRules(decoded);
    return RulesEngine(
      rules: ruleList.map(Rule.fromJson).toList(growable: false),
      noMatchOutcome: noMatchOutcome,
    );
  }

  /// Runs the rule table against [symptoms].
  ///
  /// Returns the first rule (in ascending priority) whose conditions are
  /// satisfied. If none is satisfied but some required field was `null`,
  /// returns [Outcome.needsMoreInfo] with those fields listed. Otherwise returns
  /// [noMatchOutcome].
  TriageResult evaluate(SymptomSet symptoms) {
    final missing = <String>{};
    for (final rule in rules) {
      final result = _evaluateCondition(rule.conditions, symptoms);
      if (result.satisfied) {
        return TriageResult(
          outcome: rule.outcome,
          ruleId: rule.id,
          sourceDoc: rule.sourceDoc,
          sourcePage: rule.sourcePage,
          reason: 'Matched rule "${rule.id}".',
        );
      }
      missing.addAll(result.missing);
    }

    if (missing.isNotEmpty) {
      final ordered = _orderMissing(missing);
      return TriageResult(
        outcome: Outcome.needsMoreInfo,
        missingFields: ordered,
        reason:
            'No rule matched yet: ${ordered.length} required field(s) unknown.',
      );
    }

    return TriageResult(
      outcome: noMatchOutcome,
      reason: 'No rule matched the known fields.',
    );
  }
  // ─── Condition evaluation ───────────────────────────────────────────────

  _Eval _evaluateCondition(
    Map<String, dynamic> condition,
    SymptomSet symptoms,
  ) {
    if (condition.containsKey('all_of')) {
      return _evaluateAllOf(_children(condition['all_of']), symptoms);
    }
    if (condition.containsKey('any_of')) {
      return _evaluateAnyOf(_children(condition['any_of']), symptoms);
    }
    if (condition.containsKey('field')) {
      return _evaluateField(condition, symptoms);
    }
    throw FormatException('Unrecognised condition: $condition');
  }

  _Eval _evaluateAllOf(
    List<Map<String, dynamic>> children,
    SymptomSet symptoms,
  ) {
    final missing = <String>{};
    for (final child in children) {
      final result = _evaluateCondition(child, symptoms);
      if (!result.satisfied) {
        // A definitely-false child makes the whole `all_of` false regardless of
        // any unknowns elsewhere.
        if (result.missing.isEmpty) return _Eval.definitelyFalse;
        missing.addAll(result.missing);
      }
    }
    return missing.isEmpty ? _Eval.satisfiedTrue : _Eval.unknown(missing);
  }

  _Eval _evaluateAnyOf(
    List<Map<String, dynamic>> children,
    SymptomSet symptoms,
  ) {
    final missing = <String>{};
    for (final child in children) {
      final result = _evaluateCondition(child, symptoms);
      if (result.satisfied) return _Eval.satisfiedTrue;
      missing.addAll(result.missing);
    }
    return missing.isEmpty ? _Eval.definitelyFalse : _Eval.unknown(missing);
  }

  _Eval _evaluateField(Map<String, dynamic> condition, SymptomSet symptoms) {
    final field = condition['field'];
    if (field is! String) {
      throw FormatException('Condition "field" must be a string: $condition');
    }

    final value = symptoms.valueFor(field);
    if (value == null) {
      // Unknown, NOT false: record the field and keep scanning.
      return _Eval.unknown(<String>{field});
    }

    if (condition.containsKey('is')) {
      return value == condition['is']
          ? _Eval.satisfiedTrue
          : _Eval.definitelyFalse;
    }

    if (condition.containsKey('gte')) {
      final threshold = condition['gte'];
      if (value is num && threshold is num) {
        return value >= threshold ? _Eval.satisfiedTrue : _Eval.definitelyFalse;
      }
      return _Eval.definitelyFalse;
    }

    throw FormatException(
      'Condition on "$field" needs an "is" or "gte" operator.',
    );
  }
  // ─── Helpers ────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _children(Object? raw) {
    if (raw is! List) {
      throw const FormatException(
        '"any_of" / "all_of" must be a list of conditions.',
      );
    }
    return raw
        .map((element) {
          if (element is! Map) {
            throw const FormatException(
              'Every condition in "any_of" / "all_of" must be an object.',
            );
          }
          return Map<String, dynamic>.from(element);
        })
        .toList(growable: false);
  }

  static List<Rule> _sortAscending(List<Rule> input) {
    final decorated = input.asMap().entries.toList()
      ..sort((a, b) {
        final byPriority = a.value.priority.compareTo(b.value.priority);
        if (byPriority != 0) return byPriority;
        return a.key.compareTo(b.key); // preserves input order on ties
      });
    return List<Rule>.unmodifiable(decorated.map((e) => e.value));
  }

  static List<Map<String, dynamic>> _extractRules(Object? decoded) {
    List<Object?> rawList;
    if (decoded is List) {
      rawList = decoded;
    } else if (decoded is Map && decoded['rules'] is List) {
      rawList = decoded['rules'] as List;
    } else if (decoded is Map &&
        (decoded.containsKey('conditions') || decoded.containsKey('id'))) {
      rawList = <Object?>[decoded];
    } else if (decoded is Map) {
      rawList = decoded.values.toList();
    } else {
      throw const FormatException(
        'Rules JSON must be an object with a "rules" array, a bare array, or '
        'a single rule object.',
      );
    }

    return rawList
        .map((element) {
          if (element is! Map) {
            throw const FormatException('Every rule must be a JSON object.');
          }
          return Map<String, dynamic>.from(element);
        })
        .toList(growable: false);
  }

  /// Deterministic ordering for missing fields: schema order first, then extra
  /// field names alphabetically.
  static List<String> _orderMissing(Set<String> missing) {
    final schema = SymptomSet.fieldNames
        .where(missing.contains)
        .toList(growable: false);
    final extras =
        missing.where((field) => !SymptomSet.isSchemaField(field)).toList()
          ..sort();
    return <String>[...schema, ...extras];
  }
}
