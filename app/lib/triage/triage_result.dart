/// Output type of the Dalili triage pipeline.
///
/// [TriageResult] is produced by [TriagePipeline.run] and consumed by the UI.
/// It is strictly read-only — no method mutates it after construction.
library dalili.triage.triage_result;

// ─── Action enum ─────────────────────────────────────────────────────────────

/// The clinical action the CHW must take.
///
/// Listed from highest to lowest urgency so comparisons are safe with `>`.
enum TriageAction {
  /// Immediate referral to a health facility.  One or more danger signs
  /// require inpatient or clinician-level care.
  urgentReferral,

  /// A specific follow-up question must be answered before a decision can
  /// be made.  [TriageResult.followUpQuestions] will be non-empty.
  needsFollowUp,

  /// Home care with oral treatment and watchful waiting.
  /// Return to clinic in the number of days stated in [explanation].
  homeCareTreatment,

  /// Input is outside the IMCI 2–59 month scope, or describes an adult /
  /// newborn.  The CHW should use a different protocol.
  outOfScope,
}

// ─── Citation ─────────────────────────────────────────────────────────────────

/// A single evidence reference from the domain pack or rules table.
class Citation {
  /// Short human-readable label (e.g. "IMCI Chart 2 – Cough").
  final String label;

  /// Guideline document name (e.g. "WHO IMCI Chart Booklet 2014").
  final String document;

  /// Page number in the source document, for field verification.
  final int? page;

  /// The verbatim guideline passage retrieved from the domain pack.
  final String passage;

  const Citation({
    required this.label,
    required this.document,
    required this.passage,
    this.page,
  });

  @override
  String toString() => 'Citation($label, p.$page)';
}

// ─── TriageResult ─────────────────────────────────────────────────────────────

/// The complete output of one triage run.
class TriageResult {
  /// The recommended action.  Always present.
  final TriageAction action;

  /// IDs of the IMCI rules that fired, in match order.
  /// Sourced from [rules.json].
  final List<String> firedRuleIds;

  /// Human-readable labels of the danger signs or classifications found,
  /// e.g. `["General danger sign: unable to drink", "Fast breathing"]`.
  final List<String> findings;

  /// IMCI classification name(s), e.g. `["SEVERE PNEUMONIA"]`.
  final List<String> classifications;

  /// Plain-language explanation phrased for a CHW in the field.
  /// Produced by [Explainer] (LLM or template fallback).
  final String explanation;

  /// Guideline passages cited as evidence for this recommendation.
  final List<Citation> citations;

  /// Non-empty only when [action] == [TriageAction.needsFollowUp].
  /// Contains the questions [SafetyGate] decided must be answered next.
  final List<String> followUpQuestions;

  /// Wall-clock milliseconds from pipeline start to result ready.
  final int latencyMs;

  const TriageResult({
    required this.action,
    required this.firedRuleIds,
    required this.findings,
    required this.classifications,
    required this.explanation,
    required this.citations,
    this.followUpQuestions = const [],
    this.latencyMs = 0,
  });

  /// Convenience: was a referral triggered?
  bool get requiresReferral => action == TriageAction.urgentReferral;

  /// Convenience: is more information needed?
  bool get needsMoreInfo => action == TriageAction.needsFollowUp;

  @override
  String toString() =>
      'TriageResult(action=$action, rules=$firedRuleIds, '
      'latency=${latencyMs}ms)';
}
