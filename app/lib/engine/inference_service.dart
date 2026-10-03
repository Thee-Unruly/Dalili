/// On-device inference service for Dalili's triage pipeline.
///
/// [InferenceService] is a thin, singleton façade over the llama.cpp runtime.
/// It exposes exactly the two primitive operations the pipeline needs:
///
///   * [extractSymptoms] — parse a CHW's free-text description into a
///     structured JSON symptom map (called by [SymptomExtractor]).
///   * [phraseExplanation] — stream a plain-language summary of the triage
///     decision back to the CHW (called by [Explainer]).
///
/// **Design principle**: [InferenceService] never makes clinical decisions.
/// It parses and phrases.  All triage logic lives in [RulesEngine].
///
/// **Thread safety**: llama.cpp inference is single-threaded.  Both methods
/// queue through [_inferenceQueue] so concurrent callers wait rather than
/// crash the native runtime.
library dalili.engine.inference_service;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'model_descriptor.dart';
import 'inference_params.dart';

// ─── Runtime binding placeholder ─────────────────────────────────────────────
// TODO(engine): replace with the published llama_cpp_dart (or flutter_llama)
//               binding once we confirm the package version in pubspec.yaml.
//               The interface below matches the session API used in the
//               Dalili architecture doc (§5 — Native inference runtime).

/// Abstract contract that the native llama.cpp binding must satisfy.
/// Swap in the real binding by implementing this interface.
abstract class _LlamaRuntime {
  Future<bool> loadModel(String path, {String? mmprojPath});
  Future<void> unloadModel();
  bool get isLoaded;
  Future<String> generate(String prompt, InferenceParams params);
  Stream<String> generateStream(String prompt, InferenceParams params);
  Future<void> stopGeneration();
  Future<void> dispose();
}

// ─── InferenceService ─────────────────────────────────────────────────────────

/// Singleton triage inference service.
///
/// Obtain the instance via [InferenceService.instance].
class InferenceService {
  InferenceService._internal();
  static final InferenceService _instance = InferenceService._internal();
  static InferenceService get instance => _instance;

  _LlamaRuntime? _runtime;
  ModelDescriptor? _loadedDescriptor;

  // Serialize all inference calls to avoid concurrent native access.
  final _inferenceQueue = _AsyncQueue();

  // ─── State accessors ────────────────────────────────────────────

  /// The descriptor of the currently loaded model, or `null` if no model
  /// is loaded.
  ModelDescriptor? get loadedDescriptor => _loadedDescriptor;

  /// `true` when a model is loaded and ready for inference.
  bool get isReady => _runtime?.isLoaded ?? false;

  /// `true` only on Android (the supported deployment platform for CHW use).
  bool get isPlatformSupported => Platform.isAndroid;

  // ─── Lifecycle ──────────────────────────────────────────────────

  /// Loads [descriptor] from its [ModelDescriptor.filePath].
  ///
  /// Throws [StateError] if another model is already loaded — call
  /// [unload] first.  Throws [FileSystemException] if the GGUF file is
  /// missing from the device.
  Future<void> load(ModelDescriptor descriptor, _LlamaRuntime runtime) async {
    if (isReady) {
      throw StateError(
        'Cannot load ${descriptor.id}: model ${_loadedDescriptor!.id} is '
        'already loaded.  Call unload() first.',
      );
    }

    final file = File(descriptor.filePath);
    if (!file.existsSync()) {
      throw FileSystemException(
        'GGUF file not found.  Download it to the Dalili models folder first.',
        descriptor.filePath,
      );
    }

    final ok = await runtime.loadModel(
      descriptor.filePath,
      mmprojPath: descriptor.mmprojPath,
    );
    if (!ok) {
      throw Exception('llama.cpp refused to load ${descriptor.filePath}. '
          'Check that the file is a valid GGUF and that enough RAM is free.');
    }

    _runtime = runtime;
    _loadedDescriptor = descriptor;
    debugPrint('✅ InferenceService: loaded ${descriptor.displayName}');
  }

  /// Unloads the active model and releases native memory.
  Future<void> unload() async {
    await _runtime?.unloadModel();
    _runtime = null;
    _loadedDescriptor = null;
    debugPrint('ℹ️ InferenceService: model unloaded');
  }

  // ─── Pipeline primitives ────────────────────────────────────────

  /// Parses a CHW's free-text description into a structured symptom map.
  ///
  /// Returns a decoded JSON object on success, or `null` after [maxRetries]
  /// failed attempts (the caller should surface a follow-up question rather
  /// than crashing).
  ///
  /// **Safety**: this method never returns a triage recommendation — it only
  /// extracts symptom fields.  Clinical decisions belong to [RulesEngine].
  Future<Map<String, dynamic>?> extractSymptoms({
    required String chwInput,
    required String systemPrompt,
    int maxRetries = 2,
  }) async {
    _assertReady();

    return _inferenceQueue.run(() async {
      for (int attempt = 0; attempt <= maxRetries; attempt++) {
        try {
          final raw = await _runtime!.generate(
            chwInput,
            const InferenceParams.extractor(),
          );
          final json = _parseJson(raw);
          if (json != null) return json;
          debugPrint('⚠️ extractSymptoms: JSON parse failed (attempt $attempt)');
        } catch (e) {
          debugPrint('⚠️ extractSymptoms error (attempt $attempt): $e');
        }
      }
      debugPrint('❌ extractSymptoms: gave up after $maxRetries retries');
      return null;
    });
  }

  /// Streams a plain-language phrasing of the triage result to the CHW.
  ///
  /// The [triageSummary] argument is produced by [RulesEngine] + [CitationService]
  /// and already contains the decision and evidence.  This method only adds
  /// language appropriate for a CHW in the field.
  ///
  /// Yields tokens as they are produced so the UI can render progressively.
  Stream<String> phraseExplanation({
    required String triageSummary,
    required String systemPrompt,
  }) async* {
    _assertReady();

    // Wrap the stream in the queue so it does not interleave with other calls.
    yield* _inferenceQueue.runStream(
      () => _runtime!.generateStream(
        triageSummary,
        const InferenceParams.explainer(),
      ),
    );
  }

  /// Cancels any in-progress generation.
  Future<void> stopGeneration() async {
    await _runtime?.stopGeneration();
  }

  /// Disposes all native resources.  Call from the app's dispose lifecycle.
  Future<void> dispose() async {
    await _runtime?.dispose();
    _runtime = null;
    _loadedDescriptor = null;
  }

  // ─── Helpers ────────────────────────────────────────────────────

  void _assertReady() {
    if (!isReady) {
      throw StateError(
        'InferenceService: no model loaded.  '
        'Activate a model in Settings before starting triage.',
      );
    }
  }

  /// Strips markdown fences and extracts the first complete JSON object or
  /// array from [raw].  Returns `null` if no valid JSON is found.
  static Map<String, dynamic>? _parseJson(String raw) {
    // Strip ```json … ``` fences the model sometimes adds.
    final stripped = raw
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();

    final start = stripped.indexOf('{');
    if (start == -1) return null;
    final end = stripped.lastIndexOf('}');
    if (end <= start) return null;

    try {
      return jsonDecode(stripped.substring(start, end + 1))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

// ─── AsyncQueue ──────────────────────────────────────────────────────────────

/// Minimal sequential task queue.
///
/// Ensures that llama.cpp is never called concurrently from two code paths.
class _AsyncQueue {
  Future<dynamic> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() task) {
    final next = _tail.then((_) => task());
    _tail = next.catchError((_) {}); // prevent unhandled rejection chain
    return next;
  }

  Stream<T> runStream<T>(Stream<T> Function() task) {
    // Convert the queued future into a stream via async*.
    final controller = StreamController<T>();
    _tail = _tail.then((_) async {
      await for (final token in task()) {
        controller.add(token);
      }
      await controller.close();
    }).catchError((e) {
      controller.addError(e);
      controller.close();
    });
    return controller.stream;
  }
}
