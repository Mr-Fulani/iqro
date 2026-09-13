/// Visual identity is deliberately separate from canonical Quran/audio identity.
class MushafIdentity {
  const MushafIdentity._(this.code);
  static const primary = MushafIdentity._('kfgqpc-hafs');

  factory MushafIdentity.fromPreference(String value) {
    if (!RegExp(r'^native:[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(value) ||
        value.length > 71) {
      return primary;
    }
    return MushafIdentity._(value.substring(7));
  }

  final String code;
  int? get foundationId =>
      code.startsWith('qf-') ? int.tryParse(code.substring(3)) : null;
  bool get isFoundation => foundationId != null;
  String get preference => 'native:$code';
  String get contentKey => 'mushaf-rendition:$code';
  String pageCacheKey(int page) => 'mushaf-rendition:$code:page:$page';
  String get apiPath => isFoundation
      ? '/quran/foundation/mushafs/$foundationId'
      : '/quran/mushaf-renditions/$code';

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
    this.pagesCount = 604,
    this.linesPerPage = 15,
    this.sourceChecksum = '',
  });
  final MushafIdentity identity;
  final Map<String, String> names;
  final bool stagingOnly;
  final int pagesCount;
  final int linesPerPage;
  final String sourceChecksum;

  static NativeMushafEdition? fromFoundation(Map<String, Object?> json) {
    final rendering = json['rendering'];
    final id = (json['source_id'] as num?)?.toInt() ?? 0;
    final pages = (json['pages_count'] as num?)?.toInt() ?? 0;
    final lines = (json['lines_per_page'] as num?)?.toInt() ?? 0;
    final name = json['name']?.toString().trim() ?? '';
    if (id < 1 ||
        pages < 1 ||
        pages > 1000 ||
        lines < 1 ||
        lines > 30 ||
        name.isEmpty ||
        json['qirat_name'] != 'Hafs' ||
        json['mapping_mode'] != 'reference' ||
        rendering is! Map ||
        rendering['version'] != 2 ||
        rendering['available'] != true ||
        !const {
          'page-font',
          'unicode-font',
          'word-images',
        }.contains(rendering['mode']) ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(json['source_checksum_sha256']?.toString() ?? '')) {
      return null;
    }
    return NativeMushafEdition(
      identity: MushafIdentity.fromPreference('native:qf-$id'),
      names: {'en': name},
      stagingOnly: false,
      pagesCount: pages,
      linesPerPage: lines,
      sourceChecksum: json['source_checksum_sha256'] as String,
    );
  }

  static NativeMushafEdition? parse(Map<String, Object?> json) {
    final code = json['code']?.toString() ?? '';
    final identity = MushafIdentity.fromPreference('native:$code');
    if (code == 'madani-hafs' ||
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

MushafIdentity availableMushafIdentity(
  MushafIdentity requested,
  Iterable<NativeMushafEdition> catalog, {
  required bool isProduction,
}) {
  final available = catalog
      .where((edition) => edition.availableIn(isProduction: isProduction))
      .toList();
  for (final identity in [
    requested,
    MushafIdentity.fromPreference('native:qf-5'),
    MushafIdentity.primary,
  ]) {
    if (available.any((edition) => edition.identity == identity)) {
      return identity;
    }
  }
  return available.firstOrNull?.identity ?? MushafIdentity.primary;
}
