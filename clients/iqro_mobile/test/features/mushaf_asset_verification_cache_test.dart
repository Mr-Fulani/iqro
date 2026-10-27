import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';

void main() {
  test('verified Mushaf assets avoid repeated digest reads', () async {
    final directory = await Directory.systemTemp.createTemp(
      'iqro-mushaf-verifier-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final bytes = <int>[
      0x52,
      0x49,
      0x46,
      0x46,
      0x08,
      0x00,
      0x00,
      0x00,
      0x57,
      0x45,
      0x42,
      0x50,
      0x56,
      0x50,
      0x38,
      0x20,
      0x01,
      0x02,
      0x03,
      0x04,
    ];
    final file = File('${directory.path}/page-001.webp');
    await file.writeAsBytes(bytes, flush: true);
    final checksum = sha256.convert(bytes).toString();
    var digestReads = 0;
    final verifier = MushafAssetVerificationCache(
      digestReader: (file) async {
        digestReads += 1;
        return (await sha256.bind(file.openRead()).first).toString();
      },
    );

    expect(
      await verifier.verify(file, checksum, expectedBytes: bytes.length),
      isTrue,
    );
    expect(
      await verifier.verify(file, checksum, expectedBytes: bytes.length),
      isTrue,
    );
    expect(digestReads, 1);
  });

  test('fonts are verified once with a custom header check', () async {
    final directory = await Directory.systemTemp.createTemp(
      'iqro-mushaf-verifier-',
    );
    addTearDown(() => directory.delete(recursive: true));
    // A TrueType file does not start like a WebP image.
    final bytes = List<int>.generate(64, (index) => index);
    final file = File('${directory.path}/page-604.ttf');
    await file.writeAsBytes(bytes, flush: true);
    final checksum = sha256.convert(bytes).toString();
    var digestReads = 0;
    final verifier = MushafAssetVerificationCache(
      validHeader: (_) => true,
      digestReader: (file) async {
        digestReads += 1;
        return (await sha256.bind(file.openRead()).first).toString();
      },
    );

    for (var turn = 0; turn < 3; turn++) {
      expect(
        await verifier.verify(file, checksum, expectedBytes: bytes.length),
        isTrue,
      );
    }
    expect(digestReads, 1);
    expect(
      await MushafAssetVerificationCache().verify(
        file,
        checksum,
        expectedBytes: bytes.length,
      ),
      isFalse,
    );
  });

  test('a changed Mushaf asset invalidates its verification stamp', () async {
    final directory = await Directory.systemTemp.createTemp(
      'iqro-mushaf-verifier-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final bytes = <int>[
      0x52,
      0x49,
      0x46,
      0x46,
      0x08,
      0x00,
      0x00,
      0x00,
      0x57,
      0x45,
      0x42,
      0x50,
      0x56,
      0x50,
      0x38,
      0x20,
      0x01,
      0x02,
      0x03,
      0x04,
    ];
    final file = File('${directory.path}/page-002.webp');
    await file.writeAsBytes(bytes, flush: true);
    final checksum = sha256.convert(bytes).toString();
    var digestReads = 0;
    final verifier = MushafAssetVerificationCache(
      digestReader: (file) async {
        digestReads += 1;
        return (await sha256.bind(file.openRead()).first).toString();
      },
    );
    expect(
      await verifier.verify(file, checksum, expectedBytes: bytes.length),
      isTrue,
    );

    final changed = List<int>.of(bytes)..last = 0x05;
    await file.writeAsBytes(changed, flush: true);
    await file.setLastModified(DateTime.now().add(const Duration(seconds: 2)));

    expect(
      await verifier.verify(file, checksum, expectedBytes: bytes.length),
      isFalse,
    );
    expect(digestReads, 2);
  });
}
