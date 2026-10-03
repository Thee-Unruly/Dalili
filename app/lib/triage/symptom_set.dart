/// Typed representation of all clinical data collected during one triage session.
///
/// Every nullable field means **unknown** — the CHW has not yet provided or
/// been asked for that data point.  A `null` is semantically distinct from
/// `false` (sign absent) and is the trigger for [SafetyGate] to generate a
/// follow-up question rather than letting [RulesEngine] operate on incomplete
/// evidence.
///
/// Immutable: produce a new [SymptomSet] via [copyWith] as the CHW answers
/// follow-up questions.
library dalili.triage.symptom_set;

// ─── Supporting enums ────────────────────────────────────────────────────────

/// Result of the skin-pinch test for dehydration (IMCI §3).
enum SkinPinchResult {
  /// Skin returns to normal in < 1 second.
  normal,

  /// Skin returns to normal in 1–2 seconds (some dehydration).
  slow,

  /// Skin remains up for > 2 seconds (severe dehydration).
  verySlow,
}

/// Severity of palmar pallor for anaemia screening (IMCI §7).
enum PalmarPallor {
  /// Palms normal colour.
  none,

  /// Palms pale but not very pale.
  some,

  /// Palms very pale or white.
  severe,
}

// ─── SymptomSet ──────────────────────────────────────────────────────────────

/// All clinical observations gathered for one child in one triage session.
///
/// Create via the default constructor, then narrow fields with [copyWith]
/// as the conversation progresses.
class SymptomSet {
  // ── Demographics ──────────────────────────────────────────────────────────
  /// Age in whole months.  Must be 2–59 (2 months to < 5 years).
  final int ageMonths;

  /// Weight in kilograms (optional; used for dosing guidance).
  final double? weightKg;

  // ── General danger signs (IMCI Chart 1, p. 3) ────────────────────────────

  /// Child is unable to drink or breastfeed.
  final bool? unableToDrinkOrFeed;

  /// Child vomits everything they take.
  final bool? vomitsEverything;

  /// Convulsions occurring now.
  final bool? convulsionsNow;

  /// History of convulsions in this illness episode.
  final bool? convulsionsHistory;

  /// Child is lethargic or unconscious.
  final bool? lethargicOrUnconscious;

  // ── Cough / Difficult breathing (IMCI Chart 2, p. 5–6) ──────────────────

  /// Chief complaint includes cough or difficult breathing.
  final bool? hasCough;

  /// Respiratory rate counted over one full minute.
  final int? breathsPerMinute;

  /// Lower chest wall indrawing observed.
  final bool? chestIndrawing;

  /// Stridor heard in a calm child.
  final bool? stridor;

  /// Central cyanosis (blue lips/tongue).
  final bool? centralCyanosis;

  // ── Diarrhoea (IMCI Chart 3, p. 7–8) ────────────────────────────────────

  /// Chief complaint includes diarrhoea.
  final bool? hasDiarrhoea;

  /// Duration of diarrhoea in days.
  final int? diarrhoeaDays;

  /// Blood in stool (dysentery).
  final bool? bloodInStool;

  /// Sunken eyes observed on examination.
  final bool? sunkenEyes;

  /// Skin-pinch test result (performed on abdomen).
  final SkinPinchResult? skinPinch;

  /// Child is restless or irritable.
  final bool? restlessOrIrritable;

  /// Child drinks eagerly / is very thirsty when offered water.
  final bool? drinksEagerly;

  // ── Fever (IMCI Chart 4, p. 9–11) ────────────────────────────────────────

  /// Chief complaint includes fever, or axillary temp ≥ 37.5 °C.
  final bool? hasFever;

  /// Measured temperature in degrees Celsius (axillary).
  final double? tempCelsius;

  /// Duration of fever in days.
  final int? feverDays;

  /// Stiff neck on examination.
  final bool? stiffNeck;

  /// Bulging fontanelle (infants < 12 months only).
  final bool? bulgingFontanelle;

  /// Widespread rash (used for measles / severe febrile disease).
  final bool? rash;

  /// Malaria rapid diagnostic test result.
  /// `null` = test not yet done; `true` = positive; `false` = negative.
  final bool? rdtPositive;

  /// Any runny nose (helps identify source of fever).
  final bool? runnyNose;

  // ── Ear problem (IMCI Chart 5, p. 12) ────────────────────────────────────

  /// Child complains of ear pain or parent reports ear discharge.
  final bool? earProblem;

  /// Pus observed draining from ear.
  final bool? pusDrainingFromEar;

  /// Duration of ear discharge in days.
  final int? earDischargeDays;

  /// Tender swelling behind the ear (mastoiditis sign).
  final bool? tenderSwellingBehindEar;

  // ── Malnutrition / Anaemia (IMCI Chart 6, p. 13) ─────────────────────────

  /// Mid-upper arm circumference in millimetres.
  final int? muacMm;

  /// Visible severe wasting on inspection.
  final bool? visibleSevereWasting;

  /// Bilateral pitting oedema of both feet.
  final bool? bilateralOedema;

  /// Palmar pallor severity.
  final PalmarPallor? palmarPallor;

  // ─── Constructor ──────────────────────────────────────────────────────────

  const SymptomSet({
    required this.ageMonths,
    this.weightKg,
    this.unableToDrinkOrFeed,
    this.vomitsEverything,
    this.convulsionsNow,
    this.convulsionsHistory,
    this.lethargicOrUnconscious,
    this.hasCough,
    this.breathsPerMinute,
    this.chestIndrawing,
    this.stridor,
    this.centralCyanosis,
    this.hasDiarrhoea,
    this.diarrhoeaDays,
    this.bloodInStool,
    this.sunkenEyes,
    this.skinPinch,
    this.restlessOrIrritable,
    this.drinksEagerly,
    this.hasFever,
    this.tempCelsius,
    this.feverDays,
    this.stiffNeck,
    this.bulgingFontanelle,
    this.rash,
    this.rdtPositive,
    this.runnyNose,
    this.earProblem,
    this.pusDrainingFromEar,
    this.earDischargeDays,
    this.tenderSwellingBehindEar,
    this.muacMm,
    this.visibleSevereWasting,
    this.bilateralOedema,
    this.palmarPallor,
  }) : assert(ageMonths >= 2 && ageMonths <= 59,
            'ageMonths must be 2–59 for IMCI under-5 protocol');

  // ─── Derived helpers ──────────────────────────────────────────────────────

  /// IMCI threshold for fast breathing depends on age bucket.
  /// Returns `true` if [breathsPerMinute] meets the threshold for this child's age.
  /// Returns `null` if [breathsPerMinute] has not been recorded.
  bool? get hasFastBreathing {
    if (breathsPerMinute == null) return null;
    final threshold = ageMonths < 12 ? 50 : 40;
    return breathsPerMinute! >= threshold;
  }

  /// Fast-breathing threshold for display ("≥ 50 bpm" / "≥ 40 bpm").
  int get fastBreathingThreshold => ageMonths < 12 ? 50 : 40;

  /// Any general danger sign is present (true) or absent (false).
  /// Returns `null` if any danger sign field is still unknown.
  bool? get hasAnyGeneralDangerSign {
    final signs = [
      unableToDrinkOrFeed,
      vomitsEverything,
      convulsionsNow,
      lethargicOrUnconscious,
    ];
    if (signs.any((s) => s == true)) return true;
    if (signs.any((s) => s == null)) return null;
    return false;
  }

  // ─── copyWith ─────────────────────────────────────────────────────────────

  SymptomSet copyWith({
    int? ageMonths,
    double? weightKg,
    bool? unableToDrinkOrFeed,
    bool? vomitsEverything,
    bool? convulsionsNow,
    bool? convulsionsHistory,
    bool? lethargicOrUnconscious,
    bool? hasCough,
    int? breathsPerMinute,
    bool? chestIndrawing,
    bool? stridor,
    bool? centralCyanosis,
    bool? hasDiarrhoea,
    int? diarrhoeaDays,
    bool? bloodInStool,
    bool? sunkenEyes,
    SkinPinchResult? skinPinch,
    bool? restlessOrIrritable,
    bool? drinksEagerly,
    bool? hasFever,
    double? tempCelsius,
    int? feverDays,
    bool? stiffNeck,
    bool? bulgingFontanelle,
    bool? rash,
    bool? rdtPositive,
    bool? runnyNose,
    bool? earProblem,
    bool? pusDrainingFromEar,
    int? earDischargeDays,
    bool? tenderSwellingBehindEar,
    int? muacMm,
    bool? visibleSevereWasting,
    bool? bilateralOedema,
    PalmarPallor? palmarPallor,
  }) {
    return SymptomSet(
      ageMonths: ageMonths ?? this.ageMonths,
      weightKg: weightKg ?? this.weightKg,
      unableToDrinkOrFeed: unableToDrinkOrFeed ?? this.unableToDrinkOrFeed,
      vomitsEverything: vomitsEverything ?? this.vomitsEverything,
      convulsionsNow: convulsionsNow ?? this.convulsionsNow,
      convulsionsHistory: convulsionsHistory ?? this.convulsionsHistory,
      lethargicOrUnconscious: lethargicOrUnconscious ?? this.lethargicOrUnconscious,
      hasCough: hasCough ?? this.hasCough,
      breathsPerMinute: breathsPerMinute ?? this.breathsPerMinute,
      chestIndrawing: chestIndrawing ?? this.chestIndrawing,
      stridor: stridor ?? this.stridor,
      centralCyanosis: centralCyanosis ?? this.centralCyanosis,
      hasDiarrhoea: hasDiarrhoea ?? this.hasDiarrhoea,
      diarrhoeaDays: diarrhoeaDays ?? this.diarrhoeaDays,
      bloodInStool: bloodInStool ?? this.bloodInStool,
      sunkenEyes: sunkenEyes ?? this.sunkenEyes,
      skinPinch: skinPinch ?? this.skinPinch,
      restlessOrIrritable: restlessOrIrritable ?? this.restlessOrIrritable,
      drinksEagerly: drinksEagerly ?? this.drinksEagerly,
      hasFever: hasFever ?? this.hasFever,
      tempCelsius: tempCelsius ?? this.tempCelsius,
      feverDays: feverDays ?? this.feverDays,
      stiffNeck: stiffNeck ?? this.stiffNeck,
      bulgingFontanelle: bulgingFontanelle ?? this.bulgingFontanelle,
      rash: rash ?? this.rash,
      rdtPositive: rdtPositive ?? this.rdtPositive,
      runnyNose: runnyNose ?? this.runnyNose,
      earProblem: earProblem ?? this.earProblem,
      pusDrainingFromEar: pusDrainingFromEar ?? this.pusDrainingFromEar,
      earDischargeDays: earDischargeDays ?? this.earDischargeDays,
      tenderSwellingBehindEar: tenderSwellingBehindEar ?? this.tenderSwellingBehindEar,
      muacMm: muacMm ?? this.muacMm,
      visibleSevereWasting: visibleSevereWasting ?? this.visibleSevereWasting,
      bilateralOedema: bilateralOedema ?? this.bilateralOedema,
      palmarPallor: palmarPallor ?? this.palmarPallor,
    );
  }

  @override
  String toString() => 'SymptomSet(age=${ageMonths}m, '
      'gds=${hasAnyGeneralDangerSign}, '
      'bpm=$breathsPerMinute, fever=$hasFever, '
      'diarrhoea=$hasDiarrhoea, muac=$muacMm)';
}
