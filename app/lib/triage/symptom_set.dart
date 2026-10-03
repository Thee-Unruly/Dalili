/// Neutral, pure-Dart container for the data collected about one patient.
///
/// ## Null means unknown
/// Every field is nullable. `null` means "not observed / not reported yet" and
/// is **never** treated as `false`. The rules engine turns a `null` field into
/// a follow-up question ([Outcome.needsMoreInfo]) instead of a negative
/// finding. This is what keeps the core safe on incomplete input.
///
/// ## No clinical content
/// This file deliberately contains **no** clinical signs, thresholds, or
/// classifications. It is a schema only. All clinical meaning lives in the
/// caller-supplied rules JSON and follow-up-question map.
library;

/// A snapshot of the fields the triage core knows how to reason about.
///
/// Immutable: build a new [SymptomSet] (with [copyWith]) as more answers
/// arrive.
class SymptomSet {
  /// Age of the patient in whole months.
  final int? ageMonths;

  /// Number of days the patient has had fever.
  final int? feverDays;

  /// Whether the patient has cough or difficulty breathing.
  final bool? coughOrDifficultyBreathing;

  /// Respiratory rate, in breaths per minute.
  final int? breathsPerMinute;

  /// Whether the patient is unable to drink or breastfeed.
  final bool? unableToDrinkOrBreastfeed;

  /// Whether the patient vomits everything.
  final bool? vomitsEverything;

  /// Whether the patient has convulsions.
  final bool? convulsions;

  /// Whether the patient is lethargic or unconscious.
  final bool? lethargicOrUnconscious;

  /// Whether chest indrawing is present.
  final bool? chestIndrawing;

  /// Whether stridor is present when the patient is calm.
  final bool? stridorWhenCalm;

  /// Number of days the patient has had diarrhoea.
  final int? diarrhoeaDays;

  /// Whether there is blood in the stool.
  final bool? bloodInStool;

  /// Extra, non-schema fields addressed by name.
  ///
  /// The twelve fields above are the fixed triage schema. This map lets callers
  /// carry additional names — for example clearly-fake fixture fields such as
  /// `sign_a` — without inventing clinical fields. [valueFor] checks the named
  /// fields first, then this map. It is round-tripped by [toMap]/[fromMap].
  final Map<String, Object?> additionalFields;

  const SymptomSet({
    this.ageMonths,
    this.feverDays,
    this.coughOrDifficultyBreathing,
    this.breathsPerMinute,
    this.unableToDrinkOrBreastfeed,
    this.vomitsEverything,
    this.convulsions,
    this.lethargicOrUnconscious,
    this.chestIndrawing,
    this.stridorWhenCalm,
    this.diarrhoeaDays,
    this.bloodInStool,
    this.additionalFields = const <String, Object?>{},
  });

  /// Canonical, ordered list of every schema field name.
  static const List<String> fieldNames = <String>[
    'ageMonths',
    'feverDays',
    'coughOrDifficultyBreathing',
    'breathsPerMinute',
    'unableToDrinkOrBreastfeed',
    'vomitsEverything',
    'convulsions',
    'lethargicOrUnconscious',
    'chestIndrawing',
    'stridorWhenCalm',
    'diarrhoeaDays',
    'bloodInStool',
  ];

  /// Reads a field by its string [name].
  ///
  /// Schema fields are checked first, then [additionalFields]. Returns `null`
  /// both when the field is unknown and when [name] is not carried at all; use
  /// [hasField] / [isKnown] to tell those apart.
  Object? valueFor(String name) => switch (name) {
    'ageMonths' => ageMonths,
    'feverDays' => feverDays,
    'coughOrDifficultyBreathing' => coughOrDifficultyBreathing,
    'breathsPerMinute' => breathsPerMinute,
    'unableToDrinkOrBreastfeed' => unableToDrinkOrBreastfeed,
    'vomitsEverything' => vomitsEverything,
    'convulsions' => convulsions,
    'lethargicOrUnconscious' => lethargicOrUnconscious,
    'chestIndrawing' => chestIndrawing,
    'stridorWhenCalm' => stridorWhenCalm,
    'diarrhoeaDays' => diarrhoeaDays,
    'bloodInStool' => bloodInStool,
    _ => additionalFields[name],
  };

  /// Shorthand for [valueFor].
  Object? operator [](String name) => valueFor(name);

  /// Whether [name] is one of the twelve fixed schema fields.
  static bool isSchemaField(String name) => fieldNames.contains(name);

  /// Whether [name] is carried by this set (schema field or extra field),
  /// regardless of whether its value is known.
  bool hasField(String name) =>
      isSchemaField(name) || additionalFields.containsKey(name);

  /// Whether [name] is carried *and* its value is not `null`.
  bool isKnown(String name) => hasField(name) && valueFor(name) != null;

  /// Names of every field carried by this set whose value is still `null`.
  List<String> get unknownFields {
    final names = <String>{...fieldNames, ...additionalFields.keys};
    return names
        .where((name) => valueFor(name) == null)
        .toList(growable: false);
  }

  /// Serialises to a JSON-encodable map.
  ///
  /// Unknown (`null`) schema fields are omitted; [additionalFields] are merged
  /// in (schema names win on collision).
  Map<String, Object?> toMap() {
    final map = <String, Object?>{};
    for (final name in fieldNames) {
      final value = valueFor(name);
      if (value != null) map[name] = value;
    }
    additionalFields.forEach((key, value) {
      map.putIfAbsent(key, () => value);
    });
    return map;
  }

  /// Rebuilds a [SymptomSet] from a [toMap] result.
  ///
  /// Keys that are not schema fields are kept in [additionalFields]. Values are
  /// coerced leniently (`int`/`num`/`String` for numbers, `bool`/`"true"`/
  /// `"false"` for booleans); anything unparseable becomes `null` (unknown).
  factory SymptomSet.fromMap(Map<String, Object?> map) {
    final extras = <String, Object?>{};
    map.forEach((key, value) {
      if (!isSchemaField(key)) extras[key] = value;
    });
    return SymptomSet(
      ageMonths: _asInt(map['ageMonths']),
      feverDays: _asInt(map['feverDays']),
      coughOrDifficultyBreathing: _asBool(map['coughOrDifficultyBreathing']),
      breathsPerMinute: _asInt(map['breathsPerMinute']),
      unableToDrinkOrBreastfeed: _asBool(map['unableToDrinkOrBreastfeed']),
      vomitsEverything: _asBool(map['vomitsEverything']),
      convulsions: _asBool(map['convulsions']),
      lethargicOrUnconscious: _asBool(map['lethargicOrUnconscious']),
      chestIndrawing: _asBool(map['chestIndrawing']),
      stridorWhenCalm: _asBool(map['stridorWhenCalm']),
      diarrhoeaDays: _asInt(map['diarrhoeaDays']),
      bloodInStool: _asBool(map['bloodInStool']),
      additionalFields: extras,
    );
  }

  /// Returns a copy with the supplied fields overwritten.
  ///
  /// Passing `null` leaves a field untouched; this helper cannot reset a field
  /// back to unknown. Use [toMap] minus a key and [SymptomSet.fromMap] to do
  /// that.
  SymptomSet copyWith({
    int? ageMonths,
    int? feverDays,
    bool? coughOrDifficultyBreathing,
    int? breathsPerMinute,
    bool? unableToDrinkOrBreastfeed,
    bool? vomitsEverything,
    bool? convulsions,
    bool? lethargicOrUnconscious,
    bool? chestIndrawing,
    bool? stridorWhenCalm,
    int? diarrhoeaDays,
    bool? bloodInStool,
    Map<String, Object?>? additionalFields,
  }) {
    return SymptomSet(
      ageMonths: ageMonths ?? this.ageMonths,
      feverDays: feverDays ?? this.feverDays,
      coughOrDifficultyBreathing:
          coughOrDifficultyBreathing ?? this.coughOrDifficultyBreathing,
      breathsPerMinute: breathsPerMinute ?? this.breathsPerMinute,
      unableToDrinkOrBreastfeed:
          unableToDrinkOrBreastfeed ?? this.unableToDrinkOrBreastfeed,
      vomitsEverything: vomitsEverything ?? this.vomitsEverything,
      convulsions: convulsions ?? this.convulsions,
      lethargicOrUnconscious:
          lethargicOrUnconscious ?? this.lethargicOrUnconscious,
      chestIndrawing: chestIndrawing ?? this.chestIndrawing,
      stridorWhenCalm: stridorWhenCalm ?? this.stridorWhenCalm,
      diarrhoeaDays: diarrhoeaDays ?? this.diarrhoeaDays,
      bloodInStool: bloodInStool ?? this.bloodInStool,
      additionalFields: additionalFields ?? this.additionalFields,
    );
  }

  // ─── Coercion helpers ───────────────────────────────────────────────────

  static int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool? _asBool(Object? value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is String) {
      final normalised = value.toLowerCase();
      if (normalised == 'true') return true;
      if (normalised == 'false') return false;
    }
    return null;
  }

  static bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value)
        return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SymptomSet &&
        other.ageMonths == ageMonths &&
        other.feverDays == feverDays &&
        other.coughOrDifficultyBreathing == coughOrDifficultyBreathing &&
        other.breathsPerMinute == breathsPerMinute &&
        other.unableToDrinkOrBreastfeed == unableToDrinkOrBreastfeed &&
        other.vomitsEverything == vomitsEverything &&
        other.convulsions == convulsions &&
        other.lethargicOrUnconscious == lethargicOrUnconscious &&
        other.chestIndrawing == chestIndrawing &&
        other.stridorWhenCalm == stridorWhenCalm &&
        other.diarrhoeaDays == diarrhoeaDays &&
        other.bloodInStool == bloodInStool &&
        _mapEquals(other.additionalFields, additionalFields);
  }

  @override
  int get hashCode => Object.hash(
    ageMonths,
    feverDays,
    coughOrDifficultyBreathing,
    breathsPerMinute,
    unableToDrinkOrBreastfeed,
    vomitsEverything,
    convulsions,
    lethargicOrUnconscious,
    chestIndrawing,
    stridorWhenCalm,
    diarrhoeaDays,
    bloodInStool,
    additionalFields.length,
  );

  @override
  String toString() => 'SymptomSet(${toMap()})';
}
