/// [SymptomExtractor] — converts a CHW's free-text description of a sick child
/// into a validated [SymptomSet] using on-device LLM inference.
///
/// ## Role in the pipeline
/// The extractor is the **only** module that calls the LLM during the parsing
/// phase.  It never makes a clinical decision — it only populates typed fields.
/// All triage logic lives downstream in [RulesEngine].
///
/// ## Failure behaviour
/// If the LLM produces invalid JSON after [maxRetries] attempts the extractor
/// returns `null`.  [TriagePipeline] then invokes [SafetyGate] which will
/// ask the CHW to re-describe the child or answer targeted questions.
library dalili.triage.symptom_extractor;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../engine/inference_service.dart';
import 'symptom_set.dart';

// ─── System prompt ────────────────────────────────────────────────────────────

const _kSystemPrompt = '''
You are a clinical data parser for a community health worker app used in Kenya.
Your only job is to read the CHW's description of a sick child and return a
JSON object containing exactly the fields listed below.

Rules:
- Use null for any field not mentioned or not clearly determinable.
- Use true / false only when the CHW's text makes the sign clearly present or absent.
- Do NOT guess or infer signs that are not stated.
- Do NOT add any explanation, markdown fences, or text outside the JSON object.
- The JSON must be parseable with json.decode() — no trailing commas, no comments.

Fields (all nullable unless noted):
{
  "age_months": <integer, REQUIRED, range 2–59>,
  "weight_kg": <number or null>,
  "unable_to_drink_or_feed": <bool or null>,
  "vomits_everything": <bool or null>,
  "convulsions_now": <bool or null>,
  "convulsions_history": <bool or null>,
  "lethargic_or_unconscious": <bool or null>,
  "has_cough": <bool or null>,
  "breaths_per_minute": <integer or null>,
  "chest_indrawing": <bool or null>,
  "stridor": <bool or null>,
  "central_cyanosis": <bool or null>,
  "has_diarrhoea": <bool or null>,
  "diarrhoea_days": <integer or null>,
  "blood_in_stool": <bool or null>,
  "sunken_eyes": <bool or null>,
  "skin_pinch": <"normal" | "slow" | "very_slow" | null>,
  "restless_or_irritable": <bool or null>,
  "drinks_eagerly": <bool or null>,
  "has_fever": <bool or null>,
  "temp_celsius": <number or null>,
  "fever_days": <integer or null>,
  "stiff_neck": <bool or null>,
  "bulging_fontanelle": <bool or null>,
  "rash": <bool or null>,
  "rdt_positive": <bool or null>,
  "runny_nose": <bool or null>,
  "ear_problem": <bool or null>,
  "pus_draining_from_ear": <bool or null>,
  "ear_discharge_days": <integer or null>,
  "tender_swelling_behind_ear": <bool or null>,
  "muac_mm": <integer or null>,
  "visible_severe_wasting": <bool or null>,
  "bilateral_oedema": <bool or null>,
  "palmar_pallor": <"none" | "some" | "severe" | null>
}
''';

// ─── SymptomExtractor ─────────────────────────────────────────────────────────

/// Parses free text into a validated [SymptomSet].
///
/// Backed by [InferenceService]; inject a mock for unit tests.
class SymptomExtractor {
  final InferenceService _inference;
  final int maxRetries;

  const SymptomExtractor(this._inference, {this.maxRetries = 2});

  /// Parses [chwInput] and returns a [SymptomSet], or `null` on failure.
  ///
  /// [chwInput] is the raw text or transcript the CHW entered.
  Future<SymptomSet?> extract(String chwInput) async {
    if (chwInput.trim().isEmpty) return null;

    final Map<String, dynamic>? json = await _inference.extractSymptoms(
      chwInput: chwInput,
      systemPrompt: _kSystemPrompt,
      maxRetries: maxRetries,
    );

    if (json == null) {
      debugPrint('SymptomExtractor: LLM returned no parseable JSON');
      return null;
    }

    return _mapToSymptomSet(json);
  }

  // ─── JSON → SymptomSet ───────────────────────────────────────────────────

  /// Maps the LLM's JSON object to a [SymptomSet].
  ///
  /// Unknown or misspelled values are treated as `null` (unknown) rather than
  /// throwing — a robust extractor should degrade gracefully.
  static SymptomSet? _mapToSymptomSet(Map<String, dynamic> j) {
    final ageMonths = j['age_months'];
    if (ageMonths == null) {
      debugPrint('SymptomExtractor: age_months missing — cannot build SymptomSet');
      return null;
    }

    final age = (ageMonths as num).toInt().clamp(2, 59);

    return SymptomSet(
      ageMonths: age,
      weightKg: _toDouble(j['weight_kg']),
      // General danger signs
      unableToDrinkOrFeed: _toBool(j['unable_to_drink_or_feed']),
      vomitsEverything: _toBool(j['vomits_everything']),
      convulsionsNow: _toBool(j['convulsions_now']),
      convulsionsHistory: _toBool(j['convulsions_history']),
      lethargicOrUnconscious: _toBool(j['lethargic_or_unconscious']),
      // Cough / breathing
      hasCough: _toBool(j['has_cough']),
      breathsPerMinute: _toInt(j['breaths_per_minute']),
      chestIndrawing: _toBool(j['chest_indrawing']),
      stridor: _toBool(j['stridor']),
      centralCyanosis: _toBool(j['central_cyanosis']),
      // Diarrhoea
      hasDiarrhoea: _toBool(j['has_diarrhoea']),
      diarrhoeaDays: _toInt(j['diarrhoea_days']),
      bloodInStool: _toBool(j['blood_in_stool']),
      sunkenEyes: _toBool(j['sunken_eyes']),
      skinPinch: _toSkinPinch(j['skin_pinch']),
      restlessOrIrritable: _toBool(j['restless_or_irritable']),
      drinksEagerly: _toBool(j['drinks_eagerly']),
      // Fever
      hasFever: _toBool(j['has_fever']),
      tempCelsius: _toDouble(j['temp_celsius']),
      feverDays: _toInt(j['fever_days']),
      stiffNeck: _toBool(j['stiff_neck']),
      bulgingFontanelle: _toBool(j['bulging_fontanelle']),
      rash: _toBool(j['rash']),
      rdtPositive: _toBool(j['rdt_positive']),
      runnyNose: _toBool(j['runny_nose']),
      // Ear
      earProblem: _toBool(j['ear_problem']),
      pusDrainingFromEar: _toBool(j['pus_draining_from_ear']),
      earDischargeDays: _toInt(j['ear_discharge_days']),
      tenderSwellingBehindEar: _toBool(j['tender_swelling_behind_ear']),
      // Nutrition
      muacMm: _toInt(j['muac_mm']),
      visibleSevereWasting: _toBool(j['visible_severe_wasting']),
      bilateralOedema: _toBool(j['bilateral_oedema']),
      palmarPallor: _toPalmarPallor(j['palmar_pallor']),
    );
  }

  // ─── Type coercion helpers ────────────────────────────────────────────────

  static bool? _toBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is String) {
      final s = v.toLowerCase();
      if (s == 'true') return true;
      if (s == 'false') return false;
    }
    return null;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static SkinPinchResult? _toSkinPinch(dynamic v) {
    if (v == null) return null;
    switch (v.toString().toLowerCase()) {
      case 'normal':
        return SkinPinchResult.normal;
      case 'slow':
        return SkinPinchResult.slow;
      case 'very_slow':
        return SkinPinchResult.verySlow;
      default:
        return null;
    }
  }

  static PalmarPallor? _toPalmarPallor(dynamic v) {
    if (v == null) return null;
    switch (v.toString().toLowerCase()) {
      case 'none':
        return PalmarPallor.none;
      case 'some':
        return PalmarPallor.some;
      case 'severe':
        return PalmarPallor.severe;
      default:
        return null;
    }
  }

  // ─── Test helper ─────────────────────────────────────────────────────────

  /// Parses a raw JSON string directly (useful in unit tests to bypass LLM).
  static SymptomSet? fromJsonString(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return _mapToSymptomSet(j);
    } catch (e) {
      debugPrint('SymptomExtractor.fromJsonString error: $e');
      return null;
    }
  }
}
