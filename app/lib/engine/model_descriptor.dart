/// Describes a GGUF model that Dalili can load for on-device inference.
///
/// A [ModelDescriptor] is a pure-data record — it carries every piece of
/// information the [ModelManager] needs to locate, validate, and load the
/// model without hitting the network.  It never owns native resources.
library dalili.engine.model_descriptor;

/// Quantisation family, used to estimate memory footprint and pick
/// the right context window at load time.
enum GgufQuantisation {
  /// Full precision (fp16/bf16) – highest quality, highest RAM.
  f16,

  /// 8-bit integer quantisation.
  q8_0,

  /// 4-bit, medium-quality (e.g. Q4_K_M).
  q4,

  /// 3-bit or lower – smallest footprint, lowest quality.
  q3,

  /// Quantisation level not known at registration time.
  unknown,
}

/// A registered GGUF model that Dalili can activate for triage inference.
class ModelDescriptor {
  /// Human-readable label shown in the UI (e.g. "Llama-3.2 1B Q4_K_M").
  final String displayName;

  /// Unique stable identifier used as a primary key in preferences and logs.
  /// Convention: `<family>-<params>-<quant>` in snake_case,
  /// e.g. `llama3_1b_q4km`.
  final String id;

  /// Absolute path to the `.gguf` file on the device filesystem.
  final String filePath;

  /// Quantisation level, inferred from the filename when not set explicitly.
  final GgufQuantisation quantisation;

  /// Approximate RAM required to load this model, in megabytes.
  /// Used by [HardwareGate] to block loading on under-spec devices.
  final int estimatedRamMb;

  /// Maximum context length (in tokens) supported by this model.
  /// Clamped to [contextTokens] when building a [InferenceParams].
  final int maxContextTokens;

  /// Optional path to a multimodal projector (mmproj) file.
  /// When non-null the model is treated as vision-capable.
  final String? mmprojPath;

  const ModelDescriptor({
    required this.displayName,
    required this.id,
    required this.filePath,
    required this.estimatedRamMb,
    required this.maxContextTokens,
    this.quantisation = GgufQuantisation.unknown,
    this.mmprojPath,
  });

  /// Returns `true` when the model includes a multimodal projector.
  bool get isVision => mmprojPath != null;

  @override
  String toString() =>
      'ModelDescriptor($id, ram=${estimatedRamMb}MB, ctx=$maxContextTokens)';

  @override
  bool operator ==(Object other) =>
      other is ModelDescriptor && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
