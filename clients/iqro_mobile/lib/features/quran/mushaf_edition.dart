/// Visual identity is deliberately separate from canonical Quran/audio identity.
class MushafIdentity {
  const MushafIdentity._(this.code);
  static const canonical = MushafIdentity._('madani-hafs');

  factory MushafIdentity.fromPreference(String value) {
    if (!RegExp(r'^native:[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(value) ||
        value.length > 71) {
      return canonical;
    }
    return MushafIdentity._(value.substring(7));
  }

  final String code;
  bool get isCanonical => code == canonical.code;
  String get preference => isCanonical ? 'scan' : 'native:$code';
  String get contentKey =>
      isCanonical ? 'quran-edition:$code' : 'mushaf-rendition:$code';
  String pageCacheKey(int page) => isCanonical
      ? 'quran:$code:page:$page'
      : 'mushaf-rendition:$code:page:$page';
  String get apiPath =>
      isCanonical ? '/quran/editions/$code' : '/quran/mushaf-renditions/$code';

  @override
  bool operator ==(Object other) =>
      other is MushafIdentity && other.code == code;
  @override
  int get hashCode => code.hashCode;
}

class NativeMushafEdition {
  const NativeMushafEdition({
    required this.identity,
    required this.names,
    required this.stagingOnly,
  });
  final MushafIdentity identity;
  final Map<String, String> names;
  final bool stagingOnly;

  static NativeMushafEdition? parse(Map<String, Object?> json) {
    final code = json['code']?.toString() ?? '';
    final identity = MushafIdentity.fromPreference('native:$code');
    if (identity.isCanonical ||
        identity.code != code ||
        json['available'] != true ||
        json['canonical_edition'] != 'madani-hafs' ||
        json['pages_count'] != 604 ||
        json['format'] != 'raster-regions-v1' ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(json['checksum_sha256']?.toString() ?? '') ||
        (json['version']?.toString() ?? '').isEmpty ||
        json['staging_only'] is! bool) {
      return null;
    }
    final raw = json['names'];
    if (raw is! Map || raw['en'] is! String || (raw['en'] as String).isEmpty) {
      return null;
    }
    return NativeMushafEdition(
      identity: identity,
      names: {
        for (final e in raw.entries)
          if (e.value is String) e.key.toString(): e.value as String,
      },
      stagingOnly: json['staging_only'] == true,
    );
  }

  String nameFor(String locale) => names[locale] ?? names['en']!;

  bool availableIn({required bool isProduction}) =>
      !isProduction || !stagingOnly;
}

MushafIdentity productionMushafIdentity(
  MushafIdentity requested,
  Iterable<NativeMushafEdition> catalog,
) =>
    requested.isCanonical ||
        catalog.any(
          (edition) =>
              edition.identity == requested &&
              edition.availableIn(isProduction: true),
        )
    ? requested
    : MushafIdentity.canonical;
