import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Directory under application support that keeps drawn miniatures.
const mushafThumbnailsDirectory = 'mushaf-thumbnails';

/// Bump when pages are drawn differently, so stored miniatures are redrawn.
const mushafThumbnailRevision = 1;

/// One drawn miniature: an edition's page in one source version, interface
/// language (its surah and juz labels) and width in physical pixels.
class MushafThumbnailKey {
  const MushafThumbnailKey({
    required this.edition,
    required this.version,
    required this.locale,
    required this.width,
  });

  final String edition;
  final String version;
  final String locale;
  final int width;

  String get _versionTag => sha256
      .convert(utf8.encode('$mushafThumbnailRevision:$version'))
      .toString()
      .substring(0, 16);

  /// Edition codes and locales never contain a dot.
  String get fileName => '$edition.$_versionTag.$locale.$width.png';

  @override
  bool operator ==(Object other) =>
      other is MushafThumbnailKey &&
      other.edition == edition &&
      other.version == version &&
      other.locale == locale &&
      other.width == width;

  @override
  int get hashCode => Object.hash(edition, version, locale, width);
}

/// Miniatures of each edition's page, drawn once and then shown as pictures:
/// decoded in memory for this run and stored as PNG for later runs. A new
/// source version of an edition replaces its pictures.
class MushafThumbnailCache {
  MushafThumbnailCache._(this._directory, this._stored);

  /// Keeps pictures for this run only.
  MushafThumbnailCache.memory() : this._(null, <String>{});

  /// Lists the stored pictures; none is read until a miniature asks for it.
  static Future<MushafThumbnailCache> open({
    Future<Directory> Function()? supportDirectory,
  }) async {
    try {
      final support =
          await (supportDirectory ?? getApplicationSupportDirectory)();
      final directory = Directory(
        p.join(support.path, mushafThumbnailsDirectory),
      );
      final stored = <String>{};
      if (await directory.exists()) {
        await for (final entity in directory.list()) {
          if (entity is! File) continue;
          final name = p.basename(entity.path);
          if (name.endsWith('.png')) {
            stored.add(name);
          } else {
            // An interrupted write.
            await entity.delete();
          }
        }
      }
      return MushafThumbnailCache._(directory, stored);
    } on Object {
      return MushafThumbnailCache.memory();
    }
  }

  /// Decoded pictures kept for this run: the whole picker grid fits.
  static const _memoryBudget = 32 << 20;

  final Directory? _directory;
  final Set<String> _stored;
  final _memory = <MushafThumbnailKey, ui.Image>{};
  var _memoryBytes = 0;
  final _reads = <MushafThumbnailKey, Future<bool>>{};

  /// The picture of [key] decoded in this run, or null. The caller owns the
  /// returned handle and disposes it.
  ui.Image? picture(MushafThumbnailKey key) {
    final image = _memory.remove(key);
    if (image == null) return null;
    _memory[key] = image;
    return image.clone();
  }

  /// Whether a picture of [key] is stored for [load].
  bool isStored(MushafThumbnailKey key) => _stored.contains(key.fileName);

  /// Decodes the stored picture of [key]; null when it is missing or
  /// unreadable, in which case the file is removed. The caller owns the
  /// returned handle.
  Future<ui.Image?> load(MushafThumbnailKey key) async {
    final read = _reads[key] ??= _read(key).whenComplete(() {
      _reads.remove(key);
    });
    return await read ? picture(key) : null;
  }

  Future<bool> _read(MushafThumbnailKey key) async {
    final directory = _directory;
    if (directory == null || !isStored(key)) return false;
    final file = File(p.join(directory.path, key.fileName));
    try {
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      try {
        _remember(key, (await codec.getNextFrame()).image);
      } finally {
        codec.dispose();
      }
      return true;
    } on Object {
      _stored.remove(key.fileName);
      try {
        await file.delete();
      } on Object {
        // Already gone.
      }
      return false;
    }
  }

  /// Keeps [image], taking ownership, as the picture of [key] and stores it.
  /// Pictures of the edition's other source versions are deleted.
  Future<void> save(MushafThumbnailKey key, ui.Image image) async {
    _memory.keys
        .where(
          (other) =>
              other.edition == key.edition && other.version != key.version,
        )
        .toList()
        .forEach(_forget);
    // Encoded from its own handle: memory may evict [image] meanwhile.
    final encoding = image.clone();
    _remember(key, image);
    final directory = _directory;
    if (directory == null) {
      encoding.dispose();
      return;
    }
    try {
      final bytes = await encoding.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      await directory.create(recursive: true);
      final target = File(p.join(directory.path, key.fileName));
      final partial = File('${target.path}.partial');
      await partial.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      await partial.rename(target.path);
      _stored.add(key.fileName);
      final edition = '${key.edition}.';
      final current = '${key.edition}.${key._versionTag}.';
      final stale = _stored
          .where(
            (name) => name.startsWith(edition) && !name.startsWith(current),
          )
          .toList();
      for (final name in stale) {
        _stored.remove(name);
        try {
          await File(p.join(directory.path, name)).delete();
        } on FileSystemException {
          // Already gone.
        }
      }
    } on Object {
      // Not stored: the miniature is drawn again in a later run.
    } finally {
      encoding.dispose();
    }
  }

  void _remember(MushafThumbnailKey key, ui.Image image) {
    _forget(key);
    _memory[key] = image;
    _memoryBytes += _bytes(image);
    while (_memoryBytes > _memoryBudget && _memory.length > 1) {
      _forget(_memory.keys.first);
    }
  }

  void _forget(MushafThumbnailKey key) {
    final image = _memory.remove(key);
    if (image == null) return;
    _memoryBytes -= _bytes(image);
    image.dispose();
  }

  static int _bytes(ui.Image image) => image.width * image.height * 4;
}
