/// Pre-registered GGUF models curated for Dalili's on-device triage pipeline.
///
/// These are the recommended models for CHW deployments.  Each entry is a
/// constant [ModelDescriptor] that [ModelManager] can load directly from the
/// device filesystem after the file has been placed at [filePath].
///
/// **Swap policy**: any `.gguf` file dropped into the app's documents
/// directory can be registered dynamically — this catalogue is simply the
/// curated default list shown during first-run setup.
///
/// RAM estimates are conservative (add ~15 % for KV-cache at the default
/// context length).
library dalili.engine.bundled_models;

import 'package:dalili/engine/model_descriptor.dart';

/// Catalogue of models recommended for Dalili deployments.
abstract final class BundledModels {
  BundledModels._();

  // ─── Tier 1 — Ultra-low RAM (≤ 1 GB free) ─────────────────────────────────
  // Targets entry-level Android phones (< 3 GB total RAM).

  /// Qwen-2.5 0.5B Q4_K_M — smallest usable instruction-following model.
  /// Suitable for pure symptom parsing on very constrained hardware.
  static const ModelDescriptor qwen25_05b_q4km = ModelDescriptor(
    id: 'qwen25_05b_q4km',
    displayName: 'Qwen-2.5 0.5B Q4_K_M',
    filePath: '/storage/emulated/0/Dalili/models/qwen2.5-0.5b-instruct-q4_k_m.gguf',
    quantisation: GgufQuantisation.q4,
    estimatedRamMb: 400,
    maxContextTokens: 2048,
  );

  /// Qwen-2.5 1.5B Q4_K_M — good balance of speed and parsing accuracy
  /// on mid-range phones (3–4 GB RAM).
  static const ModelDescriptor qwen25_15b_q4km = ModelDescriptor(
    id: 'qwen25_15b_q4km',
    displayName: 'Qwen-2.5 1.5B Q4_K_M',
    filePath: '/storage/emulated/0/Dalili/models/qwen2.5-1.5b-instruct-q4_k_m.gguf',
    quantisation: GgufQuantisation.q4,
    estimatedRamMb: 900,
    maxContextTokens: 4096,
  );

  // ─── Tier 2 — Mid RAM (1–2 GB free) ───────────────────────────────────────
  // Targets phones with 4–6 GB total RAM.

  /// Llama-3.2 1B Q4_K_M — Meta's small instruct model.
  /// Strong instruction following; recommended default for Tier 2 devices.
  static const ModelDescriptor llama32_1b_q4km = ModelDescriptor(
    id: 'llama32_1b_q4km',
    displayName: 'Llama-3.2 1B Q4_K_M',
    filePath: '/storage/emulated/0/Dalili/models/llama-3.2-1b-instruct-q4_k_m.gguf',
    quantisation: GgufQuantisation.q4,
    estimatedRamMb: 800,
    maxContextTokens: 4096,
  );

  /// Llama-3.2 3B Q4_K_M — preferred for the Explainer role on mid-tier
  /// devices; produces more natural clinical phrasing.
  static const ModelDescriptor llama32_3b_q4km = ModelDescriptor(
    id: 'llama32_3b_q4km',
    displayName: 'Llama-3.2 3B Q4_K_M',
    filePath: '/storage/emulated/0/Dalili/models/llama-3.2-3b-instruct-q4_k_m.gguf',
    quantisation: GgufQuantisation.q4,
    estimatedRamMb: 1900,
    maxContextTokens: 4096,
  );

  // ─── Tier 3 — High RAM (≥ 2 GB free) ──────────────────────────────────────
  // Targets flagship phones (8 GB+ total RAM).

  /// Phi-3.5 Mini 3.8B Q4_K_M — Microsoft's compact model with strong
  /// reasoning; best overall accuracy for the full triage pipeline.
  static const ModelDescriptor phi35mini_q4km = ModelDescriptor(
    id: 'phi35mini_q4km',
    displayName: 'Phi-3.5 Mini 3.8B Q4_K_M',
    filePath: '/storage/emulated/0/Dalili/models/phi-3.5-mini-instruct-q4_k_m.gguf',
    quantisation: GgufQuantisation.q4,
    estimatedRamMb: 2400,
    maxContextTokens: 4096,
  );

  // ─── Helpers ───────────────────────────────────────────────────────────────

  /// Ordered list from smallest to largest — used by [ModelManager] to pick
  /// the best model that fits within available RAM.
  static const List<ModelDescriptor> all = [
    qwen25_05b_q4km,
    qwen25_15b_q4km,
    llama32_1b_q4km,
    llama32_3b_q4km,
    phi35mini_q4km,
  ];

  /// Returns the recommended model for [availableRamMb] free RAM.
  ///
  /// Picks the largest model whose [ModelDescriptor.estimatedRamMb] fits
  /// within the available headroom.  Falls back to the smallest model if
  /// even that does not fit (the caller may then warn the user).
  static ModelDescriptor recommend(int availableRamMb) {
    // Walk from largest to smallest and return first that fits.
    for (final model in all.reversed) {
      if (model.estimatedRamMb <= availableRamMb) return model;
    }
    return qwen25_05b_q4km; // fallback — let caller surface a warning
  }
}
