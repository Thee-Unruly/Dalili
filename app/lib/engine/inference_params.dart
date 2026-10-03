/// Sampling and context parameters passed to the llama.cpp runtime
/// when starting an inference session for Dalili's triage pipeline.
///
/// Two named constructors cover the two LLM roles in the pipeline:
///   * [InferenceParams.extractor] — low-temperature, structured JSON output
///     for [SymptomExtractor] and [Explainer] drafting.
///   * [InferenceParams.explainer] — slightly warmer for natural-language
///     explanation phrasing, still deterministic enough for clinical use.
///
/// The [RulesEngine] never calls inference — it is purely deterministic and
/// receives no [InferenceParams].
library dalili.engine.inference_params;

/// Wraps every runtime knob that controls one inference call.
///
/// All fields are immutable.  Create a new [InferenceParams] rather than
/// mutating an existing one.
class InferenceParams {
  /// Maximum number of tokens to generate before the session is cut off.
  final int maxNewTokens;

  /// Sampling temperature: 0.0 = greedy (deterministic), higher = more varied.
  /// For clinical parsing keep this ≤ 0.2.
  final double temperature;

  /// Nucleus sampling cut-off.  Tokens whose cumulative probability exceeds
  /// [topP] are discarded.
  final double topP;

  /// Top-K sampling: only the [topK] highest-probability tokens are considered.
  final int topK;

  /// Repetition penalty factor.  Values slightly above 1.0 reduce loops in
  /// long explanations.
  final double repeatPenalty;

  /// Number of tokens fed as context (KV-cache size).  Must not exceed
  /// [ModelDescriptor.maxContextTokens].
  final int contextTokens;

  /// When `true` the session streams tokens back as they are produced
  /// rather than returning the full string at completion.
  final bool stream;

  const InferenceParams({
    required this.maxNewTokens,
    required this.temperature,
    required this.topP,
    required this.topK,
    required this.repeatPenalty,
    required this.contextTokens,
    this.stream = false,
  });

  // ─── Named constructors for Dalili's two LLM roles ──────────────

  /// Parameters for the [SymptomExtractor] — parses free-text into a
  /// structured JSON symptom map.
  ///
  /// Low temperature and tight top-K keep the output deterministic enough
  /// to be reliably parsed.
  const InferenceParams.extractor()
      : maxNewTokens = 512,
        temperature = 0.15,
        topP = 0.90,
        topK = 30,
        repeatPenalty = 1.05,
        contextTokens = 2048,
        stream = false;

  /// Parameters for the [Explainer] — phrases the triage recommendation in
  /// plain, encouraging language for the CHW.
  ///
  /// Slightly warmer than [extractor] to produce natural prose, but still
  /// below 0.5 to prevent hallucinated clinical detail.
  const InferenceParams.explainer()
      : maxNewTokens = 300,
        temperature = 0.40,
        topP = 0.92,
        topK = 40,
        repeatPenalty = 1.10,
        contextTokens = 1024,
        stream = true;

  /// A minimal-footprint preset for devices with < 2 GB free RAM.
  const InferenceParams.lowRam()
      : maxNewTokens = 256,
        temperature = 0.15,
        topP = 0.90,
        topK = 20,
        repeatPenalty = 1.05,
        contextTokens = 512,
        stream = false;

  @override
  String toString() =>
      'InferenceParams(maxNew=$maxNewTokens, temp=$temperature, '
      'topP=$topP, topK=$topK, ctx=$contextTokens, stream=$stream)';
}
