/// Output type of the deterministic Dalili triage core.
///
/// A [TriageResult] describes an **action**, never a diagnosis. The core never
/// names a disease or classification; when a rule fires it reports the rule's
/// [TriageResult.ruleId] and the guideline [TriageResult.sourceDoc] /
/// [TriageResult.sourcePage] that justify the action.
library;

/// The action the triage core recommends.
enum Outcome {
  /// Escalate to emergency care immediately.
  urgentReferral,

  /// Manage at a clinic: treat there, or refer for clinic-level care.
  referOrTreatAtClinic,

  /// Manage at home.
  homeCare,

  /// A decision cannot be made yet; more input is required. See
  /// [TriageResult.missingFields] and [TriageResult.followUpQuestions].
  needsMoreInfo,

  /// The input falls outside the scope of the loaded guideline.
  outOfScope,
}

/// Immutable result of one triage evaluation.
class TriageResult {
  /// The recommended action.
  final Outcome outcome;

  /// Identifier of the rule that produced this result, if any. `null` for
  /// [Outcome.needsMoreInfo] and [Outcome.outOfScope].
  final String? ruleId;

  /// Source document of the matched rule, if any.
  final String? sourceDoc;

  /// Page within [sourceDoc] of the matched rule, if any.
  final int? sourcePage;

  /// Names of the fields that were unknown (`null`) and are required before a
  /// decision is possible. Non-empty only for [Outcome.needsMoreInfo].
  final List<String> missingFields;

  /// One plain-language question per entry in [missingFields].
  /// Non-empty only for [Outcome.needsMoreInfo].
  final List<String> followUpQuestions;

  /// Short, non-clinical explanation of why this outcome was produced.
  final String reason;

  const TriageResult({
    required this.outcome,
    this.ruleId,
    this.sourceDoc,
    this.sourcePage,
    this.missingFields = const <String>[],
    this.followUpQuestions = const <String>[],
    required this.reason,
  });

  /// Whether this result is a decision (as opposed to a request for more
  /// information or an out-of-scope notice).
  bool get isDecision =>
      outcome == Outcome.urgentReferral ||
      outcome == Outcome.referOrTreatAtClinic ||
      outcome == Outcome.homeCare;

  /// Whether this result is a request for more information.
  bool get needsMoreInfo => outcome == Outcome.needsMoreInfo;

  /// Returns a copy with the supplied fields overwritten. `null` leaves a
  /// field untouched.
  TriageResult copyWith({
    Outcome? outcome,
    String? ruleId,
    String? sourceDoc,
    int? sourcePage,
    List<String>? missingFields,
    List<String>? followUpQuestions,
    String? reason,
  }) {
    return TriageResult(
      outcome: outcome ?? this.outcome,
      ruleId: ruleId ?? this.ruleId,
      sourceDoc: sourceDoc ?? this.sourceDoc,
      sourcePage: sourcePage ?? this.sourcePage,
      missingFields: missingFields ?? this.missingFields,
      followUpQuestions: followUpQuestions ?? this.followUpQuestions,
      reason: reason ?? this.reason,
    );
  }

  @override
  String toString() =>
      'TriageResult(outcome: $outcome, ruleId: $ruleId, '
      'source: $sourceDoc#$sourcePage, missing: $missingFields, '
      'questions: ${followUpQuestions.length}, reason: $reason)';
}
