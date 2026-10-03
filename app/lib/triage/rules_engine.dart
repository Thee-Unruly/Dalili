/// Deterministic IMCI rules engine for Dalili.
///
/// ## Design contract
///
/// * The engine **never calls inference**.  It reads [SymptomSet] fields and
///   applies boolean predicates.
/// * Rules are loaded from `data/rules.json` (embedded as an asset) so the
///   clinical logic can be audited and updated without recompiling the app.
/// * Evaluation is **first-match-wins** within each priority tier.  Rules are
///   sorted by [TriageRule.priority] (higher = evaluated first).
/// * A rule fires when **all** of its conditions return `true` on the supplied
///   [SymptomSet].  A condition that involves a `null` field returns `false`,
///   so an incomplete set never fires a referral rule — [SafetyGate] handles
///   the incompleteness before [RulesEngine] runs.
///
/// ## Priority tiers (align with IMCI urgency)
///
/// | Priority | Meaning                         |
/// |----------|---------------------------------|
/// | 100–199  | Immediate referral (danger signs / severe classification) |
/// | 50–99    | Treat at home with close follow-up |
/// | 1–49     | Watchful waiting / reassurance  |
library dalili.triage.rules_engine;

import 'package:flutter/foundation.dart';
import 'symptom_set.dart';
import 'triage_result.dart';

// ─── Rule model ───────────────────────────────────────────────────────────────

/// A single IMCI rule loaded from `data/rules.json`.
class TriageRule {
  /// Stable unique identifier matching the entry in `rules.json`.
  final String id;

  /// Recommended clinical action when this rule fires.
  final TriageAction action;

  /// Human-readable IMCI classification name.
  final String classification;

  /// Danger sign or finding labels produced when this rule fires.
  final List<String> findings;

  /// Priority score.  Higher = evaluated first.
  final int priority;

  /// Source location in the guideline document (for [Citation]).
  final String sourceLabel;
  final String sourceDocument;
  final int? sourcePage;

  /// The verbatim guideline passage to cite.
  final String guidelinePassage;

  /// Predicate function.  Returns `true` when [symptoms] satisfies this rule.
  /// Assigned by [RulesEngine._buildPredicate] after JSON load.
  final bool Function(SymptomSet symptoms) matches;

  const TriageRule({
    required this.id,
    required this.action,
    required this.classification,
    required this.findings,
    required this.priority,
    required this.sourceLabel,
    required this.sourceDocument,
    required this.sourcePage,
    required this.guidelinePassage,
    required this.matches,
  });
}

// ─── RulesEngine ──────────────────────────────────────────────────────────────

/// Evaluates a [SymptomSet] against the IMCI rule table and returns all
/// matching rules, ordered by priority.
///
/// Rules are registered in [_buildRules].  The JSON at `data/rules.json`
/// defines the IDs, labels, and sources; predicates are implemented here in
/// Dart to remain type-safe and testable without a JSON DSL.
///
/// **Usage**
/// ```dart
/// final engine = RulesEngine();
/// final matches = engine.evaluate(symptoms);
/// // matches.first is the highest-priority fired rule.
/// ```
class RulesEngine {
  late final List<TriageRule> _rules;

  RulesEngine() {
    _rules = _buildRules();
    // Stable sort: highest priority first.
    _rules.sort((a, b) => b.priority.compareTo(a.priority));
    debugPrint('RulesEngine: ${_rules.length} rules loaded');
  }

  /// Returns every rule that matches [symptoms], in priority order.
  ///
  /// The caller ([TriagePipeline]) typically uses [result.first] as the
  /// primary action, but collects all matches for multi-classification output.
  List<TriageRule> evaluate(SymptomSet symptoms) {
    return _rules.where((r) => r.matches(symptoms)).toList();
  }

  // ─── Rule definitions ────────────────────────────────────────────────────
  // Source: WHO IMCI Chart Booklet (2014 revision), Kenya IMCI guidelines (2016).
  // Each rule ID matches a key in data/rules.json.

  List<TriageRule> _buildRules() => [

    // ════════════════════════════════════════════════════════════════════════
    // PRIORITY 100–199 — URGENT REFERRAL
    // ════════════════════════════════════════════════════════════════════════

    // ── General danger signs (Chart 1, p. 3) ─────────────────────────────

    TriageRule(
      id: 'GDS_CONVULSIONS_NOW',
      action: TriageAction.urgentReferral,
      classification: 'GENERAL DANGER SIGN',
      findings: ['Convulsions currently occurring'],
      priority: 199,
      sourceLabel: 'IMCI Chart 1 – General Danger Signs',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 3,
      guidelinePassage:
          'A child has a general danger sign if the child: is having convulsions now. '
          'Refer URGENTLY to hospital.',
      matches: (s) => s.convulsionsNow == true,
    ),

    TriageRule(
      id: 'GDS_LETHARGY',
      action: TriageAction.urgentReferral,
      classification: 'GENERAL DANGER SIGN',
      findings: ['Lethargic or unconscious'],
      priority: 198,
      sourceLabel: 'IMCI Chart 1 – General Danger Signs',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 3,
      guidelinePassage:
          'A child has a general danger sign if the child: is lethargic or unconscious. '
          'Refer URGENTLY to hospital.',
      matches: (s) => s.lethargicOrUnconscious == true,
    ),

    TriageRule(
      id: 'GDS_UNABLE_TO_FEED',
      action: TriageAction.urgentReferral,
      classification: 'GENERAL DANGER SIGN',
      findings: ['Unable to drink or breastfeed'],
      priority: 197,
      sourceLabel: 'IMCI Chart 1 – General Danger Signs',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 3,
      guidelinePassage:
          'A child has a general danger sign if the child: is not able to drink or breastfeed. '
          'Refer URGENTLY to hospital.',
      matches: (s) => s.unableToDrinkOrFeed == true,
    ),

    TriageRule(
      id: 'GDS_VOMITS_ALL',
      action: TriageAction.urgentReferral,
      classification: 'GENERAL DANGER SIGN',
      findings: ['Vomits everything'],
      priority: 196,
      sourceLabel: 'IMCI Chart 1 – General Danger Signs',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 3,
      guidelinePassage:
          'A child has a general danger sign if the child: vomits everything. '
          'Refer URGENTLY to hospital.',
      matches: (s) => s.vomitsEverything == true,
    ),

    // ── Severe pneumonia / respiratory (Chart 2, p. 5) ────────────────────

    TriageRule(
      id: 'RESP_CYANOSIS',
      action: TriageAction.urgentReferral,
      classification: 'SEVERE PNEUMONIA OR VERY SEVERE DISEASE',
      findings: ['Central cyanosis'],
      priority: 190,
      sourceLabel: 'IMCI Chart 2 – Cough or Difficult Breathing',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 5,
      guidelinePassage:
          'Classify as SEVERE PNEUMONIA OR VERY SEVERE DISEASE if: central cyanosis. '
          'Refer URGENTLY to hospital.',
      matches: (s) => s.hasCough == true && s.centralCyanosis == true,
    ),

    TriageRule(
      id: 'RESP_CHEST_INDRAWING',
      action: TriageAction.urgentReferral,
      classification: 'SEVERE PNEUMONIA OR VERY SEVERE DISEASE',
      findings: ['Chest indrawing'],
      priority: 189,
      sourceLabel: 'IMCI Chart 2 – Cough or Difficult Breathing',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 5,
      guidelinePassage:
          'Classify as SEVERE PNEUMONIA OR VERY SEVERE DISEASE if: chest indrawing. '
          'Refer URGENTLY to hospital. Give first dose of appropriate antibiotic.',
      matches: (s) => s.hasCough == true && s.chestIndrawing == true,
    ),

    TriageRule(
      id: 'RESP_STRIDOR',
      action: TriageAction.urgentReferral,
      classification: 'SEVERE PNEUMONIA OR VERY SEVERE DISEASE',
      findings: ['Stridor in a calm child'],
      priority: 188,
      sourceLabel: 'IMCI Chart 2 – Cough or Difficult Breathing',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 5,
      guidelinePassage:
          'Classify as SEVERE PNEUMONIA OR VERY SEVERE DISEASE if: stridor in calm child. '
          'Refer URGENTLY to hospital.',
      matches: (s) => s.hasCough == true && s.stridor == true,
    ),

    // ── Severe dehydration (Chart 3, p. 7) ───────────────────────────────

    TriageRule(
      id: 'DIARR_SEVERE_DEHYDRATION',
      action: TriageAction.urgentReferral,
      classification: 'SEVERE DEHYDRATION',
      findings: ['Two or more signs of severe dehydration'],
      priority: 180,
      sourceLabel: 'IMCI Chart 3 – Diarrhoea',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 7,
      guidelinePassage:
          'Classify as SEVERE DEHYDRATION if two of the following: lethargic or unconscious; '
          'sunken eyes; not able to drink or drinks poorly; skin pinch goes back very slowly (>2 s). '
          'Refer URGENTLY to hospital with ORS.',
      matches: (s) {
        if (s.hasDiarrhoea != true) return false;
        int signs = 0;
        if (s.lethargicOrUnconscious == true) signs++;
        if (s.sunkenEyes == true) signs++;
        if (s.unableToDrinkOrFeed == true) signs++;
        if (s.skinPinch == SkinPinchResult.verySlow) signs++;
        return signs >= 2;
      },
    ),

    // ── Severe febrile disease / meningitis (Chart 4, p. 9) ──────────────

    TriageRule(
      id: 'FEVER_STIFF_NECK',
      action: TriageAction.urgentReferral,
      classification: 'VERY SEVERE FEBRILE DISEASE',
      findings: ['Stiff neck (meningism)'],
      priority: 175,
      sourceLabel: 'IMCI Chart 4 – Fever',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 9,
      guidelinePassage:
          'Classify as VERY SEVERE FEBRILE DISEASE if: stiff neck. '
          'Refer URGENTLY. Give first dose of antibiotic and antipyretic.',
      matches: (s) => s.hasFever == true && s.stiffNeck == true,
    ),

    TriageRule(
      id: 'FEVER_BULGING_FONTANELLE',
      action: TriageAction.urgentReferral,
      classification: 'VERY SEVERE FEBRILE DISEASE',
      findings: ['Bulging fontanelle'],
      priority: 174,
      sourceLabel: 'IMCI Chart 4 – Fever',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 9,
      guidelinePassage:
          'Classify as VERY SEVERE FEBRILE DISEASE if: bulging fontanelle (in infant). '
          'Refer URGENTLY.',
      matches: (s) =>
          s.hasFever == true && s.bulgingFontanelle == true && s.ageMonths < 12,
    ),

    // ── Mastoiditis (Chart 5, p. 12) ──────────────────────────────────────

    TriageRule(
      id: 'EAR_MASTOIDITIS',
      action: TriageAction.urgentReferral,
      classification: 'MASTOIDITIS',
      findings: ['Tender swelling behind the ear'],
      priority: 160,
      sourceLabel: 'IMCI Chart 5 – Ear Problem',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 12,
      guidelinePassage:
          'Classify as MASTOIDITIS if: tender swelling behind the ear. '
          'Refer URGENTLY to hospital.',
      matches: (s) => s.earProblem == true && s.tenderSwellingBehindEar == true,
    ),

    // ── Severe acute malnutrition (Chart 6, p. 13) ────────────────────────

    TriageRule(
      id: 'NUTR_SEVERE_WASTING',
      action: TriageAction.urgentReferral,
      classification: 'SEVERE ACUTE MALNUTRITION',
      findings: ['Visible severe wasting'],
      priority: 155,
      sourceLabel: 'IMCI Chart 6 – Nutritional Status',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 13,
      guidelinePassage:
          'Classify as SEVERE ACUTE MALNUTRITION if: visible severe wasting. '
          'Refer URGENTLY for inpatient nutrition management.',
      matches: (s) => s.visibleSevereWasting == true,
    ),

    TriageRule(
      id: 'NUTR_BILATERAL_OEDEMA',
      action: TriageAction.urgentReferral,
      classification: 'SEVERE ACUTE MALNUTRITION',
      findings: ['Bilateral pitting oedema of both feet (kwashiorkor)'],
      priority: 154,
      sourceLabel: 'IMCI Chart 6 – Nutritional Status',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 13,
      guidelinePassage:
          'Classify as SEVERE ACUTE MALNUTRITION if: oedema of both feet. '
          'Refer URGENTLY.',
      matches: (s) => s.bilateralOedema == true,
    ),

    TriageRule(
      id: 'NUTR_MUAC_RED',
      action: TriageAction.urgentReferral,
      classification: 'SEVERE ACUTE MALNUTRITION',
      findings: ['MUAC < 115 mm (red zone)'],
      priority: 153,
      sourceLabel: 'IMCI Chart 6 – Nutritional Status',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 13,
      guidelinePassage:
          'Classify as SEVERE ACUTE MALNUTRITION if: MUAC < 115 mm. '
          'Refer URGENTLY for therapeutic feeding.',
      matches: (s) =>
          s.ageMonths >= 6 && s.muacMm != null && s.muacMm! < 115,
    ),

    // ── Severe palmar pallor / anaemia (Chart 6, p. 13) ──────────────────

    TriageRule(
      id: 'ANAEMIA_SEVERE',
      action: TriageAction.urgentReferral,
      classification: 'SEVERE ANAEMIA',
      findings: ['Severe palmar pallor'],
      priority: 150,
      sourceLabel: 'IMCI Chart 6 – Nutritional Status',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 14,
      guidelinePassage:
          'Classify as SEVERE ANAEMIA if: severe palmar pallor. '
          'Refer URGENTLY. Give Vitamin A.',
      matches: (s) => s.palmarPallor == PalmarPallor.severe,
    ),

    // ════════════════════════════════════════════════════════════════════════
    // PRIORITY 50–99 — HOME CARE / TREAT WITH FOLLOW-UP
    // ════════════════════════════════════════════════════════════════════════

    // ── Pneumonia (Chart 2, p. 6) ─────────────────────────────────────────

    TriageRule(
      id: 'RESP_PNEUMONIA',
      action: TriageAction.homeCareTreatment,
      classification: 'PNEUMONIA',
      findings: ['Fast breathing'],
      priority: 90,
      sourceLabel: 'IMCI Chart 2 – Cough or Difficult Breathing',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 6,
      guidelinePassage:
          'Classify as PNEUMONIA if: fast breathing '
          '(≥50 bpm if age 2–11 months; ≥40 bpm if 12–59 months) and no chest indrawing or stridor. '
          'Give oral amoxicillin for 5 days. Follow up in 2 days.',
      matches: (s) =>
          s.hasCough == true &&
          s.hasFastBreathing == true &&
          s.chestIndrawing != true &&
          s.stridor != true,
    ),

    // ── Some dehydration (Chart 3, p. 8) ─────────────────────────────────

    TriageRule(
      id: 'DIARR_SOME_DEHYDRATION',
      action: TriageAction.homeCareTreatment,
      classification: 'SOME DEHYDRATION',
      findings: ['Two or more signs of some dehydration'],
      priority: 80,
      sourceLabel: 'IMCI Chart 3 – Diarrhoea',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 8,
      guidelinePassage:
          'Classify as SOME DEHYDRATION if two of the following: restless or irritable; '
          'sunken eyes; drinks eagerly / thirsty; skin pinch goes back slowly (1–2 s). '
          'Give ORS solution (Plan B). Follow up in 2 days.',
      matches: (s) {
        if (s.hasDiarrhoea != true) return false;
        int signs = 0;
        if (s.restlessOrIrritable == true) signs++;
        if (s.sunkenEyes == true) signs++;
        if (s.drinksEagerly == true) signs++;
        if (s.skinPinch == SkinPinchResult.slow) signs++;
        return signs >= 2;
      },
    ),

    // ── Malaria (Chart 4, p. 10) ─────────────────────────────────────────

    TriageRule(
      id: 'FEVER_MALARIA_POSITIVE',
      action: TriageAction.homeCareTreatment,
      classification: 'MALARIA',
      findings: ['Fever with positive malaria RDT'],
      priority: 75,
      sourceLabel: 'IMCI Chart 4 – Fever (Malaria)',
      sourceDocument: 'Kenya IMCI National Guidelines 2016',
      sourcePage: 22,
      guidelinePassage:
          'Classify as MALARIA if: fever and positive malaria RDT (in malaria-risk area). '
          'Give artemether-lumefantrine (AL) for 3 days per weight band. '
          'Give antipyretic. Follow up in 2 days if not improving.',
      matches: (s) =>
          s.hasFever == true && s.rdtPositive == true &&
          s.stiffNeck != true && s.lethargicOrUnconscious != true,
    ),

    // ── Acute ear infection (Chart 5, p. 12) ─────────────────────────────

    TriageRule(
      id: 'EAR_ACUTE_INFECTION',
      action: TriageAction.homeCareTreatment,
      classification: 'ACUTE EAR INFECTION',
      findings: ['Pus draining from ear < 14 days OR ear pain'],
      priority: 65,
      sourceLabel: 'IMCI Chart 5 – Ear Problem',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 12,
      guidelinePassage:
          'Classify as ACUTE EAR INFECTION if: pus draining < 14 days OR ear pain. '
          'Give amoxicillin for 5 days. Dry ear by wicking. Follow up in 5 days.',
      matches: (s) =>
          s.earProblem == true &&
          s.tenderSwellingBehindEar != true &&
          ((s.pusDrainingFromEar == true &&
                  (s.earDischargeDays == null || s.earDischargeDays! < 14)) ||
              (s.pusDrainingFromEar != true)),
    ),

    // ── Moderate malnutrition (Chart 6, p. 13) ────────────────────────────

    TriageRule(
      id: 'NUTR_MUAC_YELLOW',
      action: TriageAction.homeCareTreatment,
      classification: 'MODERATE ACUTE MALNUTRITION',
      findings: ['MUAC 115–125 mm (yellow zone)'],
      priority: 60,
      sourceLabel: 'IMCI Chart 6 – Nutritional Status',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 13,
      guidelinePassage:
          'Classify as MODERATE ACUTE MALNUTRITION if: MUAC 115 mm to < 125 mm. '
          'Provide supplementary food (RUSF). Counsel on feeding. Follow up in 30 days.',
      matches: (s) =>
          s.ageMonths >= 6 &&
          s.muacMm != null &&
          s.muacMm! >= 115 &&
          s.muacMm! < 125,
    ),

    // ── Some palmar pallor / anaemia ──────────────────────────────────────

    TriageRule(
      id: 'ANAEMIA_SOME',
      action: TriageAction.homeCareTreatment,
      classification: 'ANAEMIA',
      findings: ['Some palmar pallor'],
      priority: 55,
      sourceLabel: 'IMCI Chart 6 – Nutritional Status',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 14,
      guidelinePassage:
          'Classify as ANAEMIA if: some palmar pallor. '
          'Give iron and folic acid. Give anthelmintic if age ≥ 12 months. '
          'Advise to return if condition worsens. Follow up in 14 days.',
      matches: (s) => s.palmarPallor == PalmarPallor.some,
    ),

    // ── Dysentery (Chart 3, p. 8) ─────────────────────────────────────────

    TriageRule(
      id: 'DIARR_DYSENTERY',
      action: TriageAction.homeCareTreatment,
      classification: 'DYSENTERY',
      findings: ['Blood in stool'],
      priority: 72,
      sourceLabel: 'IMCI Chart 3 – Diarrhoea',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 8,
      guidelinePassage:
          'Classify as DYSENTERY if: blood in the stool. '
          'Give ciprofloxacin for 3 days. Follow up in 2 days.',
      matches: (s) => s.hasDiarrhoea == true && s.bloodInStool == true,
    ),

    // ── Persistent diarrhoea (Chart 3, p. 8) ─────────────────────────────

    TriageRule(
      id: 'DIARR_PERSISTENT',
      action: TriageAction.homeCareTreatment,
      classification: 'PERSISTENT DIARRHOEA',
      findings: ['Diarrhoea ≥ 14 days'],
      priority: 71,
      sourceLabel: 'IMCI Chart 3 – Diarrhoea',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 8,
      guidelinePassage:
          'Classify as PERSISTENT DIARRHOEA if: diarrhoea for 14 days or more. '
          'Refer for assessment. Advise the mother on feeding.',
      matches: (s) =>
          s.hasDiarrhoea == true &&
          s.diarrhoeaDays != null &&
          s.diarrhoeaDays! >= 14,
    ),

    // ── Chronic ear infection (Chart 5, p. 12) ────────────────────────────

    TriageRule(
      id: 'EAR_CHRONIC',
      action: TriageAction.homeCareTreatment,
      classification: 'CHRONIC EAR INFECTION',
      findings: ['Pus draining ≥ 14 days'],
      priority: 52,
      sourceLabel: 'IMCI Chart 5 – Ear Problem',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 12,
      guidelinePassage:
          'Classify as CHRONIC EAR INFECTION if: pus draining ≥ 14 days. '
          'Dry the ear by wicking. Follow up in 5 days. Refer if no improvement.',
      matches: (s) =>
          s.earProblem == true &&
          s.pusDrainingFromEar == true &&
          s.earDischargeDays != null &&
          s.earDischargeDays! >= 14 &&
          s.tenderSwellingBehindEar != true,
    ),

    // ════════════════════════════════════════════════════════════════════════
    // PRIORITY 1–49 — WATCHFUL WAITING / REASSURANCE
    // ════════════════════════════════════════════════════════════════════════

    // ── No pneumonia — cough or cold (Chart 2, p. 6) ─────────────────────

    TriageRule(
      id: 'RESP_NO_PNEUMONIA',
      action: TriageAction.homeCareTreatment,
      classification: 'COUGH OR COLD — NO PNEUMONIA',
      findings: ['Cough with no fast breathing, no chest indrawing, no stridor'],
      priority: 30,
      sourceLabel: 'IMCI Chart 2 – Cough or Difficult Breathing',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 6,
      guidelinePassage:
          'No signs of pneumonia or very severe disease. '
          'Soothe the throat and relieve the cough with a safe remedy. '
          'Advise the mother to return if the child is not improving in 5 days.',
      matches: (s) =>
          s.hasCough == true &&
          s.hasFastBreathing == false &&
          s.chestIndrawing != true &&
          s.stridor != true &&
          s.centralCyanosis != true,
    ),

    // ── No dehydration (Chart 3, p. 8) ───────────────────────────────────

    TriageRule(
      id: 'DIARR_NO_DEHYDRATION',
      action: TriageAction.homeCareTreatment,
      classification: 'DIARRHOEA — NO DEHYDRATION',
      findings: ['Diarrhoea without signs of dehydration'],
      priority: 25,
      sourceLabel: 'IMCI Chart 3 – Diarrhoea',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 8,
      guidelinePassage:
          'No signs of dehydration. Give extra fluid and continue feeding (Plan A). '
          'Advise mother to return if the child is not improving in 2 days or develops '
          'any danger sign.',
      matches: (s) =>
          s.hasDiarrhoea == true &&
          s.sunkenEyes != true &&
          s.skinPinch != SkinPinchResult.slow &&
          s.skinPinch != SkinPinchResult.verySlow &&
          s.lethargicOrUnconscious != true,
    ),

    // ── Fever — no malaria / no obvious cause (Chart 4, p. 10) ──────────

    TriageRule(
      id: 'FEVER_NO_MALARIA',
      action: TriageAction.homeCareTreatment,
      classification: 'FEVER — NO MALARIA',
      findings: ['Fever with negative malaria RDT'],
      priority: 20,
      sourceLabel: 'IMCI Chart 4 – Fever',
      sourceDocument: 'WHO IMCI Chart Booklet 2014',
      sourcePage: 10,
      guidelinePassage:
          'Classify as FEVER — NO MALARIA if: fever and negative malaria RDT, '
          'fever < 7 days, and no other severe classification. '
          'Give antipyretic. Advise to return if not improving in 2 days.',
      matches: (s) =>
          s.hasFever == true &&
          s.rdtPositive == false &&
          s.stiffNeck != true &&
          s.lethargicOrUnconscious != true,
    ),
  ];
}
