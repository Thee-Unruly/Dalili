/// Coarse hardware capability classification for Dalili.
///
/// At startup [HardwareGate] reads available RAM and maps it to a [DeviceTier].
/// The tier controls three things:
///   1. Which [BundledModels] entry is recommended.
///   2. Chunking parameters when indexing guideline embeddings.
///   3. Whether embedding indexing is deferred to the first query
///      (to avoid blocking app launch on slow hardware).
library dalili.engine.device_tier;

/// Three-level hardware classification.
enum DeviceTier {
  /// < 1 GB free RAM (typical entry-level Android, ≤ 3 GB total).
  low,

  /// 1–2 GB free RAM (mid-range Android, 4–6 GB total).
  mid,

  /// ≥ 2 GB free RAM (flagship Android, 8 GB+ total).
  high,
}

/// Tuning parameters derived from a [DeviceTier].
///
/// All values are conservative defaults validated against Dalili's
/// guideline corpus (~350 chunks at launch).  Adjust per profiling data.
class DeviceTierConfig {
  /// Target word count per guideline chunk when building the domain pack.
  final int chunkWords;

  /// Hard cap on the number of chunks loaded into the in-memory retrieval
  /// index at any one time.
  final int maxIndexedChunks;

  /// Number of chunks embedded per batch during indexing.
  /// Smaller batches reduce peak RAM at the cost of wall-clock time.
  final int embeddingBatchSize;

  /// Milliseconds to yield to the Flutter event loop between batches.
  /// Prevents UI jank during background indexing.
  final int yieldIntervalMs;

  /// When `true`, embedding indexing is skipped at document-load time and
  /// deferred until the first triage query is submitted.
  /// Set to `true` on [DeviceTier.low] to minimise startup latency.
  final bool deferIndexing;

  const DeviceTierConfig({
    required this.chunkWords,
    required this.maxIndexedChunks,
    required this.embeddingBatchSize,
    required this.yieldIntervalMs,
    required this.deferIndexing,
  });

  // ─── Tier presets ─────────────────────────────────────────────

  /// Config for [DeviceTier.low] — smallest memory footprint, indexing
  /// deferred, largest chunks to keep the index small.
  static const DeviceTierConfig low = DeviceTierConfig(
    chunkWords: 300,
    maxIndexedChunks: 60,
    embeddingBatchSize: 2,
    yieldIntervalMs: 20,
    deferIndexing: true,
  );

  /// Config for [DeviceTier.mid] — balanced throughput, no deferral.
  static const DeviceTierConfig mid = DeviceTierConfig(
    chunkWords: 175,
    maxIndexedChunks: 150,
    embeddingBatchSize: 5,
    yieldIntervalMs: 8,
    deferIndexing: false,
  );

  /// Config for [DeviceTier.high] — maximum retrieval precision, no yield
  /// delays needed.
  static const DeviceTierConfig high = DeviceTierConfig(
    chunkWords: 150,
    maxIndexedChunks: 350,
    embeddingBatchSize: 12,
    yieldIntervalMs: 0,
    deferIndexing: false,
  );

  // ─── Factory ──────────────────────────────────────────────────

  /// Returns the [DeviceTierConfig] matching [tier].
  static DeviceTierConfig forTier(DeviceTier tier) => switch (tier) {
        DeviceTier.low => low,
        DeviceTier.mid => mid,
        DeviceTier.high => high,
      };

  // ─── Tier detection helper ────────────────────────────────────

  /// Classifies [availableRamMb] into a [DeviceTier].
  ///
  /// [availableRamMb] should be the free RAM reported by the OS,
  /// not total installed RAM, so we do not over-commit.
  static DeviceTier classify(int availableRamMb) {
    if (availableRamMb >= 2000) return DeviceTier.high;
    if (availableRamMb >= 1000) return DeviceTier.mid;
    return DeviceTier.low;
  }

  @override
  String toString() =>
      'DeviceTierConfig(chunks=$chunkWords, maxIdx=$maxIndexedChunks, '
      'batch=$embeddingBatchSize, yield=${yieldIntervalMs}ms, '
      'defer=$deferIndexing)';
}
